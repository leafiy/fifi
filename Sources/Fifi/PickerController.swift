import AppKit
import Carbon.HIToolbox
import FifiCore
import SwiftUI

@MainActor
final class PickerController {
    private let historyService: HistoryService
    private let blobStore: BlobStore
    private let settingsStore: SettingsStore
    private let viewModel: PickerViewModel
    private let panel: PickerPanel

    private var returnApp: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?

    init(historyService: HistoryService, blobStore: BlobStore, settingsStore: SettingsStore) {
        self.historyService = historyService
        self.blobStore = blobStore
        self.settingsStore = settingsStore
        self.viewModel = PickerViewModel(historyService: historyService)

        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        let loader = ThumbnailLoader(blobStore: blobStore)
        let contentView = PickerHostingView(rootView: PickerView(viewModel: viewModel, thumbnailLoader: loader))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.masksToBounds = true
        panel.contentView = contentView

        viewModel.onActivate = { [weak self] item in
            Task { @MainActor in
                self?.activate(item: item)
            }
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        returnApp = NSWorkspace.shared.frontmostApplication
        positionPanel()
        viewModel.reload()
        installMonitors()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        viewModel.focusToken += 1
    }

    func hide() {
        panel.orderOut(nil)
        removeMonitors()
    }

    func activate(item: ClipboardItem) {
        PasteboardWriter.copy(item, blobStore: blobStore)
        historyService.markUsed(id: item.id)
        let app = returnApp
        hide()

        guard settingsStore.settings.selectionBehavior == .paste else { return }
        app?.activate(options: [.activateIgnoringOtherApps])
        // Give the previous app time to regain key focus before synthesizing ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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

    private func installMonitors() {
        removeMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Local monitors always fire on the main thread; route the non-Sendable
            // NSEvent through a captured var so assumeIsolated returns Void.
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                if self.panel.isVisible, self.handleKey(event) {
                    result = nil
                }
            }
            return result
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let location = event.locationInWindow
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                if !self.panel.frame.contains(location) {
                    self.hide()
                }
            }
        }
    }

    private func removeMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
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
        // deinit is nonisolated: touch stored properties directly instead of removeMonitors().
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    }
}

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PickerHostingView<Content: View>: NSHostingView<Content> {
    // The panel is non-activating and the app stays in the background, so the
    // first click must act on the row instead of being eaten as a focus click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
