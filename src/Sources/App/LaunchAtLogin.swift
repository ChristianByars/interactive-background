import Observation
import ServiceManagement
import WallpaperEngine

/// Launch at login via `SMAppService.mainApp`. macOS owns the state (it is also editable in
/// System Settings > General > Login Items), so nothing is cached or persisted here.
@MainActor
@Observable
final class LaunchAtLogin {
    /// Bumped after every change so views re-read the live status.
    private var revision = 0

    var status: SMAppService.Status {
        _ = revision
        return SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }

    /// On failure the status is left as macOS reports it, so the menu check mark stays truthful.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.login.error("Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        revision += 1
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
