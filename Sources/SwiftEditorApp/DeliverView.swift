import SwiftUI
import SwiftEditorAPI
import CoreMediaPlus
import CommandBus

/// Export/deliver panel for rendering the timeline to a file.
/// Shown in the Deliver workspace.
struct DeliverView: View {
    let engine: SwiftEditorEngine

    @State private var selectedFormat: ExportFormat = .h264
    @State private var selectedResolution: ExportResolution = .r1080p
    @State private var selectedFrameRate: ExportFrameRate = .fps24
    @State private var outputPath: String = "~/Desktop/export.mp4"
    @State private var exportError: String?
    @State private var exportComplete = false
    @State private var exportTask: Task<Void, Never>?

    private var isExporting: Bool { engine.export.isExporting }
    private var exportProgress: Double { Double(engine.export.progress) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Deliver")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlassSidebarHeader()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Format
                    GroupBox("Format") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Codec", selection: $selectedFormat) {
                                ForEach(ExportFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityLabel("Export codec")
                            .accessibilityValue(selectedFormat.displayName)

                            Picker("Resolution", selection: $selectedResolution) {
                                ForEach(ExportResolution.allCases) { res in
                                    Text(res.displayName).tag(res)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityLabel("Export resolution")
                            .accessibilityValue(selectedResolution.displayName)

                            Picker("Frame Rate", selection: $selectedFrameRate) {
                                ForEach(ExportFrameRate.allCases) { fps in
                                    Text(fps.displayName).tag(fps)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityLabel("Export frame rate")
                            .accessibilityValue(selectedFrameRate.displayName)
                        }
                    }

                    // Output
                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Output Path", text: $outputPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)

                                Button("Browse...") {
                                    browseOutputLocation()
                                }
                                .font(.caption)
                                .accessibilityLabel("Browse output location")
                                .accessibilityHint("Open a file dialog to choose the export destination")
                            }

                            HStack {
                                Text("Duration:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(formatDuration(engine.timeline.duration))
                                    .font(.caption.monospaced())
                            }

                            HStack {
                                Text("Est. Size:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(estimatedSize)
                                    .font(.caption.monospaced())
                            }
                        }
                    }

                    // Export status
                    if isExporting {
                        VStack(spacing: 8) {
                            ProgressView(value: exportProgress) {
                                Text("Exporting...")
                                    .font(.caption)
                            }
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Export progress")
                            .accessibilityValue("\(Int(exportProgress * 100)) percent")

                            Text("\(Int(exportProgress * 100))%")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)

                            Button("Cancel") {
                                cancelExport()
                            }
                            .font(.caption)
                            .accessibilityLabel("Cancel export")
                            .accessibilityHint("Stop the current export operation")
                        }
                    } else if exportComplete {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityHidden(true)
                                Text("Export Complete")
                                    .font(.caption)
                            }
                            Button("Reveal in Finder") {
                                let url = resolveOutputURL()
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                                exportComplete = false
                            }
                            .font(.caption)
                            .accessibilityLabel("Reveal in Finder")
                            .accessibilityHint("Open the exported file location in Finder")
                        }
                    } else if let error = exportError {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .accessibilityHidden(true)
                                Text("Export Failed")
                                    .font(.caption)
                            }
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Button("Dismiss") {
                                exportError = nil
                            }
                            .font(.caption)
                            .accessibilityLabel("Dismiss error")
                            .accessibilityHint("Clear the export error message")
                        }
                    } else {
                        Button {
                            startExport()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.doc")
                                Text("Start Render")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .liquidGlassProminentButton()
                        .disabled(engine.timeline.duration <= .zero)
                        .accessibilityLabel("Start Render")
                        .accessibilityHint("Begin exporting the timeline with the selected format settings")
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Export Logic

    private func startExport() {
        let outputURL = resolveOutputURL()
        let preset = mapToExportPreset()

        exportError = nil
        exportComplete = false

        exportTask = Task {
            do {
                try await engine.export.export(to: outputURL, preset: preset)
                await MainActor.run {
                    exportComplete = true
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        exportError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
    }

    private func resolveOutputURL() -> URL {
        let expanded = NSString(string: outputPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    /// Map the UI picker selections to the backend ExportPreset enum.
    private func mapToExportPreset() -> ExportPreset {
        switch selectedFormat {
        case .h264:
            return selectedResolution == .r4k ? .h264_4k : .h264_1080p
        case .h265:
            return selectedResolution == .r4k ? .h265_4k : .h265_1080p
        case .prores422:
            return .prores422
        case .prores4444:
            return .prores4444
        case .proresProxy:
            return .proresProxy
        }
    }

    private func browseOutputLocation() {
        let panel = NSSavePanel()
        panel.title = "Export Location"
        panel.nameFieldStringValue = URL(fileURLWithPath: outputPath).lastPathComponent
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]

        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    private func formatDuration(_ time: Rational) -> String {
        let total = time.seconds
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        let frames = Int((total - Double(Int(total))) * 24)
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }

    private var estimatedSize: String {
        let durationSec = engine.timeline.duration.seconds
        guard durationSec > 0 else { return "--" }
        let bitrate = selectedFormat.estimatedBitrateMbps * selectedResolution.bitrateMultiplier
        let sizeMB = bitrate * durationSec / 8
        if sizeMB > 1024 {
            return String(format: "%.1f GB", sizeMB / 1024)
        }
        return String(format: "%.0f MB", sizeMB)
    }
}

// MARK: - Export Configuration Types

enum ExportFormat: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case h265 = "H.265"
    case prores422 = "ProRes 422"
    case prores4444 = "ProRes 4444"
    case proresProxy = "ProRes Proxy"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var estimatedBitrateMbps: Double {
        switch self {
        case .h264: return 20
        case .h265: return 15
        case .prores422: return 147
        case .prores4444: return 330
        case .proresProxy: return 36
        }
    }
}

enum ExportResolution: String, CaseIterable, Identifiable {
    case r720p = "720p"
    case r1080p = "1080p"
    case r4k = "4K UHD"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var bitrateMultiplier: Double {
        switch self {
        case .r720p: return 0.44
        case .r1080p: return 1.0
        case .r4k: return 4.0
        }
    }
}

enum ExportFrameRate: String, CaseIterable, Identifiable {
    case fps24 = "24"
    case fps25 = "25"
    case fps30 = "30"
    case fps60 = "60"

    var id: String { rawValue }
    var displayName: String { rawValue + " fps" }
}
