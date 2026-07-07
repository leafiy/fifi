import ApplicationServices
import AppKit
import Foundation
import FifiCore

@MainActor enum PasteboardWriter {
    private static var didPromptForAccessibility = false

    static func copy(_ item: ClipboardItem, blobStore: BlobStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wrote = false
        switch item.type {
        case .text, .richText, .color:
            wrote = pasteboard.setString(text(for: item, blobStore: blobStore), forType: .string)
        case .url:
            let value = text(for: item, blobStore: blobStore)
            wrote = pasteboard.setString(value, forType: .string)
            _ = pasteboard.setString(value, forType: .URL)
        case .image:
            wrote = writeImage(item, blobStore: blobStore, to: pasteboard)
        case .file:
            wrote = writeFiles(item, to: pasteboard)
        case .unknown:
            wrote = pasteboard.setString(item.previewText, forType: .string)
        }

        NotificationCenter.default.post(
            name: .fifiPasteboardDidSelfWrite,
            object: nil,
            userInfo: ["changeCount": pasteboard.changeCount]
        )
        NSLog("Fifi[pasteboard] copy id=%ld type=%@ ok=%d changeCount=%ld",
              item.id, item.type.rawValue, wrote ? 1 : 0, pasteboard.changeCount)
    }

    enum ColorFormat { case hex, rgb, hsl }

    /// Copies the item's textual value as plain `.string` regardless of type.
    static func copyPlainText(_ item: ClipboardItem, blobStore: BlobStore) {
        writeString(plainText(for: item, blobStore: blobStore), item: item)
    }

    /// Copies a color item formatted as HEX, RGB, or HSL. Falls back to the
    /// raw value when the item is not a parseable color.
    static func copyColor(_ item: ClipboardItem, format: ColorFormat, blobStore: BlobStore) {
        let raw = text(for: item, blobStore: blobStore)
        let value: String
        if let color = ColorValue(hexString: raw) {
            switch format {
            case .hex: value = color.hexString
            case .rgb: value = color.rgbString
            case .hsl: value = color.hslString
            }
        } else {
            value = raw
        }
        writeString(value, item: item)
    }

    /// Copies a URL with known tracking parameters stripped.
    static func copyCleanedURL(_ item: ClipboardItem, blobStore: BlobStore) {
        let raw = text(for: item, blobStore: blobStore)
        let cleaned = URLCleaner.cleaned(raw) ?? raw
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wrote = pasteboard.setString(cleaned, forType: .string)
        _ = pasteboard.setString(cleaned, forType: .URL)
        postSelfWrite(pasteboard: pasteboard, item: item, wrote: wrote)
    }

    /// Reveals the item's first file in Finder.
    static func revealInFinder(_ item: ClipboardItem) {
        let paths = filePaths(for: item)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens a URL item in the default browser.
    static func openURL(_ item: ClipboardItem, blobStore: BlobStore) {
        let raw = text(for: item, blobStore: blobStore).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme != nil else { return }
        NSWorkspace.shared.open(url)
    }

    static func filePaths(for item: ClipboardItem) -> [String] {
        (item.fileReference ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func writeString(_ value: String, item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let wrote = pasteboard.setString(value, forType: .string)
        postSelfWrite(pasteboard: pasteboard, item: item, wrote: wrote)
    }

    private static func postSelfWrite(pasteboard: NSPasteboard, item: ClipboardItem, wrote: Bool) {
        NotificationCenter.default.post(
            name: .fifiPasteboardDidSelfWrite,
            object: nil,
            userInfo: ["changeCount": pasteboard.changeCount]
        )
        NSLog("Fifi[pasteboard] quick-action id=%ld ok=%d changeCount=%ld",
              item.id, wrote ? 1 : 0, pasteboard.changeCount)
    }

    private static func plainText(for item: ClipboardItem, blobStore: BlobStore) -> String {
        switch item.type {
        case .file:
            return filePaths(for: item).joined(separator: "\n")
        case .image:
            return item.previewText
        default:
            return text(for: item, blobStore: blobStore)
        }
    }

    static func paste() {
        guard accessibilityTrusted() else {
            warnAccessibilityOnce()
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            NSLog("Fifi failed to create paste keyboard events")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func text(for item: ClipboardItem, blobStore: BlobStore) -> String {
        if let blobPath = item.blobPath {
            do {
                let data = try blobStore.data(atRelativePath: blobPath)
                if let value = String(data: data, encoding: .utf8) {
                    return value
                }
            } catch {
                NSLog("Fifi failed to read text blob %@: %@", blobPath, String(describing: error))
            }
        }
        return item.contentText ?? item.previewText
    }

    private static func writeImage(_ item: ClipboardItem, blobStore: BlobStore, to pasteboard: NSPasteboard) -> Bool {
        guard let blobPath = item.blobPath else {
            NSLog("Fifi image item is missing blob path")
            return false
        }

        do {
            let data = try blobStore.data(atRelativePath: blobPath)
            let ext = URL(fileURLWithPath: blobPath).pathExtension.lowercased()
            return pasteboard.setData(data, forType: ext == "tiff" || ext == "tif" ? .tiff : .png)
        } catch {
            NSLog("Fifi failed to read image blob %@: %@", blobPath, String(describing: error))
            return false
        }
    }

    private static func writeFiles(_ item: ClipboardItem, to pasteboard: NSPasteboard) -> Bool {
        let paths = (item.fileReference ?? "")
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            return pasteboard.setString(item.previewText, forType: .string)
        }

        let urls = paths.map { URL(fileURLWithPath: $0) as NSURL as NSPasteboardWriting }
        let wrote = pasteboard.writeObjects(urls)
        _ = pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        return wrote
    }

    private static func accessibilityTrusted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if !didPromptForAccessibility {
            didPromptForAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if AXIsProcessTrustedWithOptions(options) {
                return true
            }
        }

        NSLog("Fifi needs Accessibility permission to paste into the frontmost app")
        return false
    }

    private static var warnedAccessibility = false

    private static func warnAccessibilityOnce() {
        guard !warnedAccessibility else { return }
        warnedAccessibility = true
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Fifi can’t paste automatically")
        alert.informativeText = L("The item WAS copied — press ⌘V to paste it manually.\n\nFor automatic paste, enable Fifi under System Settings → Privacy & Security → Accessibility. After rebuilding the app you must re-add it (the ad-hoc signature changes every build).")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("OK"))
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
