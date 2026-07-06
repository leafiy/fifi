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
        pasteboard.setData(Data(), forType: markerType)

        switch item.type {
        case .text, .richText, .color:
            pasteboard.setString(text(for: item, blobStore: blobStore), forType: .string)
        case .url:
            let value = text(for: item, blobStore: blobStore)
            pasteboard.setString(value, forType: .string)
            if let url = URL(string: value) {
                pasteboard.writeObjects([url as NSURL as NSPasteboardWriting])
            }
        case .image:
            writeImage(item, blobStore: blobStore, to: pasteboard)
        case .file:
            writeFiles(item, to: pasteboard)
        case .unknown:
            pasteboard.setString(item.previewText, forType: .string)
        }

    }

    static func paste() {
        guard accessibilityTrusted() else { return }
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

    private static func writeImage(_ item: ClipboardItem, blobStore: BlobStore, to pasteboard: NSPasteboard) {
        guard let blobPath = item.blobPath else {
            NSLog("Fifi image item is missing blob path")
            return
        }

        do {
            let data = try blobStore.data(atRelativePath: blobPath)
            let ext = URL(fileURLWithPath: blobPath).pathExtension.lowercased()
            pasteboard.setData(data, forType: ext == "tiff" || ext == "tif" ? .tiff : .png)
        } catch {
            NSLog("Fifi failed to read image blob %@: %@", blobPath, String(describing: error))
        }
    }

    private static func writeFiles(_ item: ClipboardItem, to pasteboard: NSPasteboard) {
        let paths = (item.fileReference ?? "")
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !paths.isEmpty else {
            pasteboard.setString(item.previewText, forType: .string)
            return
        }

        let urls = paths.map { URL(fileURLWithPath: $0) as NSURL as NSPasteboardWriting }
        pasteboard.writeObjects(urls)
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
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
}
