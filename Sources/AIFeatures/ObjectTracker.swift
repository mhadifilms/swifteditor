// AIFeatures — Object tracking and face analysis using Vision
import AVFoundation
import CoreMedia
import Vision

/// Tracks a single object across video frames using VNSequenceRequestHandler.
/// Wraps Vision's VNTrackObjectRequest for multi-frame tracking.
public final class ObjectTracker: @unchecked Sendable {
    private let sequenceHandler = VNSequenceRequestHandler()
    private var currentObservation: VNDetectedObjectObservation?
    private let useAccurateTracking: Bool
    private let minimumConfidence: Float

    public init(
        useAccurateTracking: Bool = true,
        minimumConfidence: Float = 0.3
    ) {
        self.useAccurateTracking = useAccurateTracking
        self.minimumConfidence = minimumConfidence
    }

    /// Initialize tracking with a bounding box (normalized Vision coordinates).
    public func startTracking(boundingBox: CGRect) {
        currentObservation = VNDetectedObjectObservation(boundingBox: boundingBox)
    }

    /// Track the object in the next frame. Returns updated bounding box or nil if lost.
    public func trackNextFrame(_ pixelBuffer: CVPixelBuffer) -> CGRect? {
        guard let observation = currentObservation else { return nil }

        var updatedObservation: VNDetectedObjectObservation?

        let request = VNTrackObjectRequest(detectedObjectObservation: observation) { request, _ in
            guard let results = request.results as? [VNDetectedObjectObservation],
                  let result = results.first else {
                return
            }
            updatedObservation = result
        }
        request.trackingLevel = useAccurateTracking ? .accurate : .fast

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            currentObservation = nil
            return nil
        }

        if let result = updatedObservation, result.confidence >= minimumConfidence {
            currentObservation = result
            return result.boundingBox
        } else {
            currentObservation = nil
            return nil
        }
    }

    /// Whether tracking is currently active.
    public var isTracking: Bool {
        currentObservation != nil
    }

    /// Reset the tracker, discarding current observation.
    public func reset() {
        currentObservation = nil
    }
}

/// Tracks multiple objects simultaneously using batched VNTrackObjectRequests.
public final class MultiObjectTracker: @unchecked Sendable {
    private let sequenceHandler = VNSequenceRequestHandler()
    private var observations: [UUID: VNDetectedObjectObservation] = [:]
    private let useAccurateTracking: Bool
    private let minimumConfidence: Float

    public init(
        useAccurateTracking: Bool = false,
        minimumConfidence: Float = 0.3
    ) {
        self.useAccurateTracking = useAccurateTracking
        self.minimumConfidence = minimumConfidence
    }

    /// Add a new object to track with a bounding box (normalized Vision coordinates).
    /// Returns the UUID assigned to this tracked object.
    @discardableResult
    public func addObject(boundingBox: CGRect) -> UUID {
        let id = UUID()
        observations[id] = VNDetectedObjectObservation(boundingBox: boundingBox)
        return id
    }

    /// Remove a tracked object by ID.
    public func removeObject(_ id: UUID) {
        observations.removeValue(forKey: id)
    }

    /// Track all objects in the next frame. Returns a dictionary of ID to updated bounding box.
    /// Objects that are lost are automatically removed.
    public func trackNextFrame(_ pixelBuffer: CVPixelBuffer) -> [UUID: CGRect] {
        guard !observations.isEmpty else { return [:] }

        let entries = Array(observations)
        var requests: [(UUID, VNTrackObjectRequest)] = []

        for (id, obs) in entries {
            let request = VNTrackObjectRequest(detectedObjectObservation: obs)
            request.trackingLevel = useAccurateTracking ? .accurate : .fast
            requests.append((id, request))
        }

        do {
            try sequenceHandler.perform(requests.map(\.1), on: pixelBuffer)
        } catch {
            observations.removeAll()
            return [:]
        }

        var results: [UUID: CGRect] = [:]
        for (id, request) in requests {
            if let visionResults = request.results as? [VNDetectedObjectObservation],
               let result = visionResults.first,
               result.confidence >= minimumConfidence {
                observations[id] = result
                results[id] = result.boundingBox
            } else {
                observations.removeValue(forKey: id)
            }
        }

        return results
    }

    /// IDs of all currently tracked objects.
    public var trackedObjectIDs: Set<UUID> {
        Set(observations.keys)
    }
}

// MARK: - Face Analysis

/// Information about a detected face in a video frame.
public struct FaceInfo: Sendable {
    public let boundingBox: CGRect
    public let roll: Float?
    public let yaw: Float?
    public let confidence: Float

    public init(boundingBox: CGRect, roll: Float?, yaw: Float?, confidence: Float) {
        self.boundingBox = boundingBox
        self.roll = roll
        self.yaw = yaw
        self.confidence = confidence
    }
}

/// Detects and analyzes faces in video frames using Vision's face landmark detection.
public struct FaceAnalyzer: Sendable {
    public init() {}

    /// Detect all faces in a frame with landmark details.
    public func detectFaces(in pixelBuffer: CVPixelBuffer) throws -> [FaceInfo] {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        return observations.map { observation in
            FaceInfo(
                boundingBox: observation.boundingBox,
                roll: observation.roll?.floatValue,
                yaw: observation.yaw?.floatValue,
                confidence: observation.confidence
            )
        }
    }

    /// Detect face capture quality for selecting best thumbnail frames.
    /// Returns array of (boundingBox, quality) tuples sorted by quality descending.
    public func detectFaceQuality(in pixelBuffer: CVPixelBuffer) throws -> [(boundingBox: CGRect, quality: Float)] {
        let request = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try handler.perform([request])

        let results = request.results?.compactMap { observation -> (CGRect, Float)? in
            guard let quality = observation.faceCaptureQuality else { return nil }
            return (observation.boundingBox, quality)
        } ?? []

        return results.sorted { $0.1 > $1.1 }
    }
}
