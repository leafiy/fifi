import AppKit
import Carbon.HIToolbox
import FifiCore
import LeafiyUICore
import LeafiyUI
import SwiftUI
@preconcurrency import UserNotifications
// The picker uses the Base Library Floating Panel: non-activating, keyboard
// capable, and shown without NSApp.activate so the frontmost app keeps focus
// for paste-through behavior.
@MainActor
final class PickerController {
    private let historyService: HistoryService
    private let blobStore: BlobStore
    private let settingsStore: SettingsStore
    private let captureCurrentPasteboard: () -> Void
    private let viewModel: PickerViewModel
    private let panel: LeafiyFloatingPanel
    private let thumbnailLoader: ThumbnailLoader
    private let quickShareService: QuickShareService

    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var historyObserver: NSObjectProtocol?
    private var lastHideTime: TimeInterval = 0
    private var languageObserver: NSObjectProtocol?

    init(
        historyService: HistoryService,
        blobStore: BlobStore,
        settingsStore: SettingsStore,
        captureCurrentPasteboard: @escaping () -> Void
    ) {
        self.historyService = historyService
        self.blobStore = blobStore
        self.settingsStore = settingsStore
        self.captureCurrentPasteboard = captureCurrentPasteboard
        self.viewModel = PickerViewModel(historyService: historyService)
        self.thumbnailLoader = ThumbnailLoader(blobStore: blobStore)
        self.quickShareService = QuickShareService(blobStore: blobStore)
        let panel = LeafiyFloatingPanel(
            configuration: LeafiyFloatingPanelConfiguration(
                canBecomeKey: true,
                isMovable: true,
                hasShadow: true
            ),
            content: Self.pickerContent(
                viewModel: viewModel,
                settingsStore: settingsStore,
                thumbnailLoader: thumbnailLoader,
                blobStore: blobStore
            )
        )
        panel.setContentSize(NSSize(width: 420, height: 480))
        panel.title = L("Clipboard History")
        panel.animationBehavior = .none
        self.panel = panel

        viewModel.onActivate = { [weak self] item in
            Task { @MainActor in
                self?.activate(item: item)
            }
        }
        viewModel.onCopyToClipboard = { [weak self] item in
            Task { @MainActor in
                self?.copyToClipboard(item: item, hideAfterCopy: false)
            }
        }
        viewModel.onQuickAction = { [weak self] action, item in
            Task { @MainActor in
                self?.performQuickAction(action, item: item)
            }
        }

        // Refresh cached recents whenever the monitor captures a new item, but
        // never while the user is mid-search.
        historyObserver = NotificationCenter.default.addObserver(
            forName: .fifiHistoryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.viewModel.query.isEmpty else { return }
                self.viewModel.reload()
            }
        }

        languageObserver = NotificationCenter.default.addObserver(
            forName: LeafiyLocalization.languageDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalizedContent()
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
        captureCurrentPasteboard()
        applySettingsToViewModel()
        resizePanel()
        positionPanel()
        viewModel.reload()
        installKeyMonitor()
        installOutsideClickMonitor()
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

    func resizeToSettings() {
        resizePanel()
        if panel.isVisible {
            positionPanel()
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        lastHideTime = ProcessInfo.processInfo.systemUptime
        removeKeyMonitor()
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    func activate(item: ClipboardItem) {
        NSLog("Fifi[picker] activating item id=%ld type=%@", item.id, item.type.rawValue)
        copyToClipboard(item: item, hideAfterCopy: false)
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

    private func copyToClipboard(item: ClipboardItem, hideAfterCopy: Bool) {
        NSLog("Fifi[picker] copying item id=%ld type=%@ hide=%d", item.id, item.type.rawValue, hideAfterCopy ? 1 : 0)
        PasteboardWriter.copy(item, blobStore: blobStore)
        historyService.markUsed(id: item.id)
        if hideAfterCopy {
            hide()
        }
    }

    private func applySettingsToViewModel() {
        let settings = settingsStore.settings
        viewModel.sortOrder = settings.sortOrder
        viewModel.fuzzyRanking = settings.fuzzyRanking
        viewModel.numberShortcuts = settings.numberShortcuts
    }

    private func resizePanel() {
        let settings = settingsStore.settings
        let width = CGFloat(settings.pickerWidth) + (settings.showPreviewPanel ? PickerView.previewPanelWidth : 0)
        let height = CGFloat(settings.pickerHeight)
        guard panel.frame.width != width || panel.frame.height != height else { return }
        panel.setContentSize(NSSize(width: width, height: height))
    }

    private func performQuickAction(_ action: PickerQuickAction, item: ClipboardItem) {
        switch action {
        case .copyPlainText:
            PasteboardWriter.copyPlainText(item, blobStore: blobStore)
            historyService.markUsed(id: item.id)
        case .copyColorHex:
            PasteboardWriter.copyColor(item, format: .hex, blobStore: blobStore)
            historyService.markUsed(id: item.id)
        case .copyColorRGB:
            PasteboardWriter.copyColor(item, format: .rgb, blobStore: blobStore)
            historyService.markUsed(id: item.id)
        case .copyColorHSL:
            PasteboardWriter.copyColor(item, format: .hsl, blobStore: blobStore)
            historyService.markUsed(id: item.id)
        case .copyCleanURL:
            PasteboardWriter.copyCleanedURL(item, blobStore: blobStore)
            historyService.markUsed(id: item.id)
        case .openURL:
            PasteboardWriter.openURL(item, blobStore: blobStore)
            hide()
        case .revealInFinder:
            PasteboardWriter.revealInFinder(item)
            hide()
        case .quickLook:
            let urls = PasteboardWriter.filePaths(for: item).map { URL(fileURLWithPath: $0) }
            QuickLookController.shared.preview(urls: urls)
        case .quickShare:
            quickShare(item)
        }
    }

    private func quickShare(_ item: ClipboardItem) {
        let settings = settingsStore.settings.quickShare
        NotificationCenter.default.post(
            name: .fifiQuickShareUploadStatusDidChange,
            object: nil,
            userInfo: ["isUploading": true]
        )
        Task { [weak self] in
            defer {
                NotificationCenter.default.post(
                    name: .fifiQuickShareUploadStatusDidChange,
                    object: nil,
                    userInfo: ["isUploading": false]
                )
            }
            guard let self else { return }
            do {
                let result = try await quickShareService.share(item: item, settings: settings)
                PasteboardWriter.copyQuickShareLinks(result.clipboardText)
                historyService.markUsed(id: item.id)
                notifyQuickShareSuccess(linkCount: result.links.count)
            } catch {
                presentQuickShareError(error)
            }
        }
    }

    private func notifyQuickShareSuccess(linkCount: Int) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = L("Quick Share complete")
            content.body = linkCount == 1
                ? L("Public link copied to clipboard.")
                : String(format: L("%d public links copied to clipboard."), linkCount)
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "com.leafiy.fifi.quick-share-complete-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }

    private func presentQuickShareError(_ error: Error) {
        NSLog("Fifi quick share failed: %@", String(describing: error))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Quick Share failed")
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.addButton(withTitle: L("OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 420, height: 480)
        let size = panel.frame.size

        let margin: CGFloat = 12
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - size.width - margin)
        let minY = visibleFrame.minY + size.height + margin
        let maxY = max(minY, visibleFrame.maxY - margin)

        // Below-right of the pointer, nudged up-left so the cursor lands just
        // inside the panel's top-left corner; the clamps above slide it back
        // on-screen near edges.
        let pointerOffset: CGFloat = 16
        let topLeft = NSPoint(
            x: min(max(mouse.x - pointerOffset, minX), maxX),
            y: min(max(mouse.y + pointerOffset, minY), maxY)
        )
        panel.setFrameTopLeftPoint(topLeft)
        NSLog(
            "Fifi[picker] positioned x=%.1f y=%.1f screen=(%.1f %.1f %.1f %.1f)",
            topLeft.x,
            topLeft.y,
            visibleFrame.minX,
            visibleFrame.minY,
            visibleFrame.width,
            visibleFrame.height
        )
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

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                self.hideIfOutsidePanel(at: Self.screenPoint(for: event))
            }
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let point = Self.screenPoint(for: event)
            Task { @MainActor in
                self?.hideIfOutsidePanel(at: point)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func hideIfOutsidePanel(at point: NSPoint) {
        guard panel.isVisible, !panel.frame.contains(point) else { return }
        NSLog("Fifi[picker] outside click hide x=%.1f y=%.1f", point.x, point.y)
        hide()
    }

    private static func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        if settingsStore.settings.numberShortcuts, modifiers == .command,
           let index = Self.shortcutIndex(for: keyCode) {
            viewModel.copyShortcutItem(at: index)
            hide()
            return true
        }

        if (modifiers.isEmpty || modifiers == .function || modifiers.contains(.command)), keyCode == kVK_Delete {
            viewModel.deleteSelected()
            return true
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            viewModel.togglePinSelected()
            return true
        }
        if modifiers.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "y" {
            if let item = viewModel.selectedItem, item.type == .file {
                performQuickAction(.quickLook, item: item)
            }
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

    private static func shortcutIndex(for keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        case kVK_ANSI_0: return 9
        default: return nil
        }
    }

    private static func pickerContent(
        viewModel: PickerViewModel,
        settingsStore: SettingsStore,
        thumbnailLoader: ThumbnailLoader,
        blobStore: BlobStore
    ) -> some View {
        PickerView(viewModel: viewModel, settingsStore: settingsStore, thumbnailLoader: thumbnailLoader, blobStore: blobStore)
            .id(settingsStore.appLanguage)
            .ignoresSafeArea()
            .clipShape(.rect(cornerRadius: 12))
    }

    private func refreshLocalizedContent() {
        panel.title = L("Clipboard History")
        panel.setContent(Self.pickerContent(
            viewModel: viewModel,
            settingsStore: settingsStore,
            thumbnailLoader: thumbnailLoader,
            blobStore: blobStore
        ))
    }

    deinit {
        // deinit is nonisolated: touch stored properties directly.
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let historyObserver { NotificationCenter.default.removeObserver(historyObserver) }
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
    }
}

