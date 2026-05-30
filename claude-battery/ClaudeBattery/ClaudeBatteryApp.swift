import SwiftUI

@main
struct ClaudeBatteryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — app lives entirely in the menu bar.
        // Settings is presented as a sheet from PopoverView or via the
        // context menu NSWindow in MenuBarManager.
        Settings {
            SettingsView()
                .environmentObject(PreferencesManager.shared)
        }
    }
}
