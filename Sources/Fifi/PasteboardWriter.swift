import ApplicationServices
import AppKit
import Foundation
import FifiCore

@MainActor enum PasteboardWriter {
    static let markerType = NSPasteboard.PasteboardType("com.leafiy.fifi.self-write")

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

        // Marker last: its failure must never block the real content, and its
        // presence tells the monitor to skip this self-write.
        _ = pasteboard.setData(Data(), forType: markerType)
        NSLog("Fifi[pasteboard] copy id=%ld type=%@ ok=%d changeCount=%ld",
              item.id, item.type.rawValue, wrote ? 1 : 0, pasteboard.changeCount)
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
        alert.messageText = "Fifi can’t paste automatically"
        alert.informativeText = "The item WAS copied — press ⌘V to paste it manually.\n\nFor automatic paste, enable Fifi under System Settings → Privacy & Security → Accessibility. After rebuilding the app you must re-add it (the ad-hoc signature changes every build)."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}
