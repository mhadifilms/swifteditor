import Foundation
import SwiftUI
import Sparkle

/// Manages automatic updates via the Sparkle framework.
///
/// Wraps `SPUStandardUpdaterController` to provide a SwiftUI-friendly interface
/// for checking and installing updates from the configured appcast feed.
@MainActor
final class UpdateManager: ObservableObject {

    private let updaterController: SPUStandardUpdaterController

    /// Whether the updater is currently able to check for updates.
    @Published var canCheckForUpdates = false

    init() {
        // Only auto-start Sparkle in release builds with a valid appcast configured.
        // In debug builds the updater cannot function (no code signing / no appcast URL)
        // and would log a distracting error on launch.
        #if DEBUG
        let shouldStart = false
        #else
        let shouldStart = Bundle.main.infoDictionary?["SUFeedURL"] != nil
        #endif

        updaterController = SPUStandardUpdaterController(
            startingUpdater: shouldStart,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe Sparkle's canCheckForUpdates property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Trigger a manual check for updates, showing the Sparkle update UI.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// The underlying SPUUpdater, exposed for advanced configuration.
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Whether automatic update checks are enabled.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// The interval between automatic update checks, in seconds.
    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }
}

// MARK: - SwiftUI Commands

/// Adds "Check for Updates..." to the app menu.
struct CheckForUpdatesCommand: Commands {
    @ObservedObject var updateManager: UpdateManager

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                updateManager.checkForUpdates()
            }
            .disabled(!updateManager.canCheckForUpdates)
        }
    }
}
