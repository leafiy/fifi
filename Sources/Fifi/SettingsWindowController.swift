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
            contentRect: NSRect(origin: .zero, size: SettingsView.Pane.general.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fifi Settings"
        window.minSize = NSSize(width: 500, height: 220)
        window.isReleasedWhenClosed = false

        let view = SettingsView(
            historyService: historyService,
            ignoreRulesStore: ignoreRulesStore,
            monitorReload: monitorReload,
            onPaneChanged: { [weak window] pane in
                Self.resize(window, toContentSize: pane.windowSize)
            }
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

    private static func resize(_ window: NSWindow?, toContentSize size: NSSize) {
        guard let window else { return }
        let frame = window.frame
        let contentRect = window.contentRect(forFrameRect: frame)
        guard abs(contentRect.width - size.width) > 0.5 || abs(contentRect.height - size.height) > 0.5 else {
            return
        }
        var nextFrame = window.frameRect(forContentRect: NSRect(origin: contentRect.origin, size: size))
        nextFrame.origin.y = frame.maxY - nextFrame.height
        window.setFrame(nextFrame, display: true, animate: window.isVisible)
    }
}
