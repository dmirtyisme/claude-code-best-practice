import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarManager {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var eventMonitor: Any?
    private let viewModel: UsageViewModel
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        configurePopover()
        subscribeToUpdates()
        viewModel.startAutoRefresh()
    }

    // MARK: - Status Item Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.title = "⏳"
        button.action = #selector(togglePopover)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    // MARK: - Popover

    private func configurePopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 340)
        popover.behavior = .transient
        popover.animates = true

        let contentView = PopoverView(viewModel: viewModel)
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()

        // Close when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Right-click context menu

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refreshAction), keyEquivalent: "r")
            .also { $0.target = self })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .also { $0.target = self })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Claude Battery", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshAction() {
        Task { await viewModel.refresh() }
    }

    @objc private func openSettings() {
        let settingsView = SettingsView().environmentObject(PreferencesManager.shared)
        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Claude Battery Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 420, height: 560))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Live title updates

    private func subscribeToUpdates() {
        viewModel.$usageData
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTitle()
            }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .receive(on: RunLoop.main)
            .sink { [weak self] error in
                if error != nil { self?.statusItem.button?.title = "⚠️" }
            }
            .store(in: &cancellables)
    }

    private func updateTitle() {
        statusItem.button?.title = viewModel.menuBarTitle
    }
}

// MARK: - NSMenuItem builder helper

private extension NSMenuItem {
    func also(_ configure: (NSMenuItem) -> Void) -> NSMenuItem {
        configure(self)
        return self
    }
}
