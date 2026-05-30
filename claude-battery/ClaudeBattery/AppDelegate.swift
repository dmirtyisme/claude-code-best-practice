import AppKit
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarManager: MenuBarManager!
    private let viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — menu bar only app
        NSApp.setActivationPolicy(.accessory)

        menuBarManager = MenuBarManager(viewModel: viewModel)
        menuBarManager.setup()

        applyLaunchAtLoginIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // Keep running with only the menu bar item
    }

    // MARK: - Launch at login (macOS 13+)

    private func applyLaunchAtLoginIfNeeded() {
        guard #available(macOS 13, *) else { return }
        let shouldLaunch = PreferencesManager.shared.preferences.launchAtLogin
        do {
            if shouldLaunch {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Non-fatal — user can re-enable in System Settings > Login Items
        }
    }
}
