import AppKit
import SwiftUI
import FifiCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private var didCenter = false

    init(
        settingsStore: SettingsStore,
        historyService: HistoryService,
        ignoreRulesStore: IgnoreRulesStore,
        monitorReload: @escaping () -> Void
    ) {
        // Initial size only; the window stays freely resizable with no min/max
        // clamp, and the grouped forms adapt to whatever size the user picks.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fifi Settings"
        window.isReleasedWhenClosed = false

        let view = SettingsView(
            historyService: historyService,
            ignoreRulesStore: ignoreRulesStore,
            monitorReload: monitorReload
        )
        .environmentObject(settingsStore)
        window.contentView = NSHostingView(rootView: view)

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        if !didCenter {
            window.center()
            didCenter = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
