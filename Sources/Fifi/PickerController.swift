import AppKit
import Carbon.HIToolbox
import FifiCore
import SwiftUI

// Panel behavior cloned from Maccy's FloatingPanel: a non-activating,
// titled-but-chromeless panel that takes key status WITHOUT activating the
// app. NSApp.activate is deliberately never called — macOS 14+ throttles
// repeated activate/yield cycles, which made the picker work only once.
@MainActor
final class PickerController {
    private let historyService: HistoryService
    private let blobStore: BlobStore
    private let settingsStore: SettingsStore
    private let viewModel: PickerViewModel
    private let panel: PickerPanel

    private var localKeyMonitor: Any?
    private var historyObserver: NSObjectProtocol?
    private var lastHideTime: TimeInterval = 0

    init(historyService: HistoryService, blobStore: BlobStore, settingsStore: SettingsStore) {
        self.historyService = historyService
        self.blobStore = blobStore
        self.settingsStore = settingsStore
        self.viewModel = PickerViewModel(historyService: historyService)

        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.nonactivatingPanel, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.animationBehavior = .none
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        self.panel = panel

        let loader = ThumbnailLoader(blobStore: blobStore)
        let contentView = PickerHostingView(
            rootView: PickerView(viewModel: viewModel, thumbnailLoader: loader)
                .ignoresSafeArea()
        )
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true
        panel.contentView = contentView

        // Click outside → panel resigns key → hide (Maccy behavior).
        panel.onResignKey = { [weak self] in
            self?.hide()
        }

        viewModel.onActivate = { [weak self] item in
            Task { @MainActor in
                self?.activate(item: item)
            }
        }

        // Refresh the visible list when the monitor captures a new item, but
        // never while the user is mid-search.
        historyObserver = NotificationCenter.default.addObserver(
            forName: .fifiHistoryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible, self.viewModel.query.isEmpty else { return }
                self.viewModel.reload()
            }
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        // A click on the status item first makes the panel resign key (hide),
        // then delivers the button action (toggle → show). Without this guard
        // the panel would instantly reopen instead of closing.
        guard ProcessInfo.processInfo.systemUptime - lastHideTime > 0.2 else { return }
        NSLog("Fifi[picker] show()")
        positionPanel()
        viewModel.reload()
        installKeyMonitor()
        panel.orderFrontRegardless()
        panel.makeKey()
        viewModel.focusToken += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            Task { @MainActor in
                guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
                NSLog("Fifi[picker] panel not key after show (appActive=%d)", NSApp.isActive ? 1 : 0)
                self.panel.makeKey()
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        lastHideTime = ProcessInfo.processInfo.systemUptime
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func activate(item: ClipboardItem) {
        NSLog("Fifi[picker] activating item id=%ld type=%@", item.id, item.type.rawValue)
        PasteboardWriter.copy(item, blobStore: blobStore)
        historyService.markUsed(id: item.id)
        hide()

        guard settingsStore.settings.selectionBehavior == .paste else { return }
        // The frontmost app never lost active status (the panel is
        // non-activating), so ⌘V lands there once key focus returns to it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task { @MainActor in
                PasteboardWriter.paste()
            }
        }
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 420, height: 480)
        let size = panel.frame.size

        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - size.width
        let minY = visibleFrame.minY + size.height
        let maxY = visibleFrame.maxY

        let topLeft = NSPoint(
            x: min(max(mouse.x, minX), maxX),
            y: min(max(mouse.y, minY), maxY)
        )
        panel.setFrameTopLeftPoint(topLeft)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                if self.panel.isVisible, self.handleKey(event) {
                    result = nil
                }
            }
            return result
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        if modifiers.contains(.command), keyCode == kVK_Delete {
            viewModel.deleteSelected()
            return true
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            viewModel.togglePinSelected()
            return true
        }

        switch keyCode {
        case kVK_UpArrow:
            viewModel.moveSelection(-1)
            return true
        case kVK_DownArrow:
            viewModel.moveSelection(1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            viewModel.activateSelected()
            return true
        case kVK_Escape:
            hide()
            return true
        default:
            return false
        }
    }

    deinit {
        // deinit is nonisolated: touch stored properties directly.
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
    }
}

private final class PickerPanel: NSPanel {
    var onResignKey: (() -> Void)?

    // Allow text inputs inside the panel to receive focus (Maccy).
    override var canBecomeKey: Bool { true }

    // Close automatically when key status is lost, e.g. an outside click.
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

private final class PickerHostingView<Content: View>: NSHostingView<Content> {
    // The panel never activates the app, so the first click must act on the
    // row instead of being eaten as a focus click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
