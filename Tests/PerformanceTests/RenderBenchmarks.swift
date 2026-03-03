import XCTest
@preconcurrency import AVFoundation
@testable import RenderEngine
@testable import EffectsEngine
@testable import CoreMediaPlus

/// Performance benchmarks for the render pipeline.
final class RenderBenchmarks: XCTestCase {

    // MARK: - RenderPlanBuilder Benchmarks

    func testBuildRenderPlan50Tracks20Clips() {
        let builder = RenderPlanBuilder()

        // Build 50 tracks x 20 clips = 1000 total clips
        var tracks: [CompositionBuilder.TrackBuildData] = []
        for _ in 0..<50 {
            var clips: [CompositionBuilder.ClipBuildData] = []
            for j in 0..<20 {
                clips.append(CompositionBuilder.ClipBuildData(
                    clipID: UUID(),
                    asset: nil,
                    startTime: Rational(Int64(j * 48), 1),
                    sourceIn: Rational(0, 1),
                    sourceOut: Rational(48, 1)
                ))
            }
            tracks.append(CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: clips
            ))
        }

        measure {
            // Build render plan at 100 different times across the timeline
            for i in 0..<100 {
                let time = Rational(Int64(i * 10), 1)
                let _ = builder.buildPlan(
                    tracks: tracks,
                    compositionTime: time,
                    renderSize: CGSize(width: 1920, height: 1080)
                )
            }
        }
    }

    func testBuildRenderPlanSingleFrameLookup() {
        let builder = RenderPlanBuilder()

        // 10 tracks x 100 clips
        var tracks: [CompositionBuilder.TrackBuildData] = []
        for _ in 0..<10 {
            var clips: [CompositionBuilder.ClipBuildData] = []
            for j in 0..<100 {
                clips.append(CompositionBuilder.ClipBuildData(
                    clipID: UUID(),
                    asset: nil,
                    startTime: Rational(Int64(j * 24), 1),
                    sourceIn: Rational(0, 1),
                    sourceOut: Rational(24, 1)
                ))
            }
            tracks.append(CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: clips
            ))
        }

        measure {
            // 1000 single-frame lookups at random times
            for _ in 0..<1000 {
                let time = Rational(Int64.random(in: 0..<2400), 1)
                let _ = builder.buildPlan(
                    tracks: tracks,
                    compositionTime: time,
                    renderSize: CGSize(width: 3840, height: 2160)
                )
            }
        }
    }

    // MARK: - FrameCacheOptimizer Benchmarks

    func testFrameCacheInsert1000Entries() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 1024 * 1024 * 1024  // 1 GB to avoid eviction
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                for i in 0..<1000 {
                    let hash = FrameHash(
                        clipID: clipID,
                        sourceTime: Rational(Int64(i), 24),
                        effectStackHash: 0
                    )
                    // Create a minimal pixel buffer for testing
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferCreate(
                        kCFAllocatorDefault,
                        2, 2,
                        kCVPixelFormatType_32BGRA,
                        nil,
                        &pixelBuffer
                    )
                    if let pb = pixelBuffer {
                        await cache.store(
                            .pixelBuffer(pb),
                            for: hash,
                            estimatedBytes: 16
                        )
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    func testFrameCacheLookup1000Entries() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 1024 * 1024 * 1024
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        // Pre-populate with 1000 entries
        for i in 0..<1000 {
            let hash = FrameHash(
                clipID: clipID,
                sourceTime: Rational(Int64(i), 24),
                effectStackHash: 0
            )
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                2, 2,
                kCVPixelFormatType_32BGRA,
                nil,
                &pixelBuffer
            )
            if let pb = pixelBuffer {
                await cache.store(.pixelBuffer(pb), for: hash, estimatedBytes: 16)
            }
        }

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                for i in 0..<1000 {
                    let hash = FrameHash(
                        clipID: clipID,
                        sourceTime: Rational(Int64(i), 24),
                        effectStackHash: 0
                    )
                    let _ = await cache.hit(for: hash)
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    func testFrameCacheEvictionUnderPressure() async {
        let config = FrameCacheOptimizer.Configuration(
            memoryBudgetBytes: 10_000,  // Very small budget to force eviction
            evictionThreshold: 0.8
        )
        let cache = FrameCacheOptimizer(configuration: config)
        let clipID = UUID()

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                for i in 0..<500 {
                    let hash = FrameHash(
                        clipID: clipID,
                        sourceTime: Rational(Int64(i), 24),
                        effectStackHash: 0
                    )
                    var pixelBuffer: CVPixelBuffer?
                    CVPixelBufferCreate(
                        kCFAllocatorDefault,
                        2, 2,
                        kCVPixelFormatType_32BGRA,
                        nil,
                        &pixelBuffer
                    )
                    if let pb = pixelBuffer {
                        await cache.store(.pixelBuffer(pb), for: hash, estimatedBytes: 100)
                    }
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    // MARK: - ShaderCache Hash Key Benchmark

    func testShaderCacheHashKey1000Sources() {
        // Generate shader source strings of varying lengths
        let sources: [String] = (0..<1000).map { i in
            """
            #include <metal_stdlib>
            using namespace metal;
            fragment float4 frag\(i)(float4 in [[stage_in]]) {
                return float4(\(Float(i) / 1000.0), 0.0, 1.0, 1.0);
            }
            """
        }

        measure {
            for source in sources {
                let _ = ShaderCache.hashKey(for: source)
            }
        }
    }

    // MARK: - CompositionBuilder Benchmark

    func testCompositionBuildEmptyTimeline() {
        let builder = CompositionBuilder()

        measure {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                for _ in 0..<100 {
                    let _ = try? await builder.buildComposition(
                        videoTracks: [],
                        audioTracks: [],
                        renderSize: CGSize(width: 1920, height: 1080),
                        frameDuration: CMTime(value: 1, timescale: 24)
                    )
                }
                semaphore.signal()
            }
            semaphore.wait()
        }
    }

    // MARK: - RenderPlan Hash Benchmark

    func testRenderPlanHashPerformance() {
        let builder = RenderPlanBuilder()

        var tracks: [CompositionBuilder.TrackBuildData] = []
        for _ in 0..<20 {
            var clips: [CompositionBuilder.ClipBuildData] = []
            for j in 0..<50 {
                clips.append(CompositionBuilder.ClipBuildData(
                    clipID: UUID(),
                    asset: nil,
                    startTime: Rational(Int64(j * 24), 1),
                    sourceIn: Rational(0, 1),
                    sourceOut: Rational(24, 1)
                ))
            }
            tracks.append(CompositionBuilder.TrackBuildData(
                trackID: UUID(),
                clips: clips
            ))
        }

        // Pre-build plans
        let plans = (0..<100).map { i in
            builder.buildPlan(
                tracks: tracks,
                compositionTime: Rational(Int64(i * 12), 1),
                renderSize: CGSize(width: 1920, height: 1080)
            )
        }

        measure {
            for plan in plans {
                let _ = plan.frameHash
            }
        }
    }
}
