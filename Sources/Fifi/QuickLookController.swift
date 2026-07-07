import AppKit
import Foundation
import Quartz

/// Drives a shared `QLPreviewPanel` for file clipboard entries. Retained by the
/// picker so its data source stays alive while the panel is visible.
@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()

    private var urls: [URL] = []

    func preview(urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        self.urls = existing
        panel.dataSource = self
        panel.delegate = self
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }
}

extension QuickLookController: @MainActor QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}

extension QuickLookController: @MainActor QLPreviewPanelDelegate {
    func previewPanelDidClose(_ panel: QLPreviewPanel) {
        urls = []
    }
}
