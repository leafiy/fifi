import AppKit
import FifiCore
import LeafiyUI
import SwiftUI

/// Right-hand detail panel showing the full content of the selected item plus
/// type-specific quick actions.
struct PreviewPanel: View {
    let item: ClipboardItem?
    let blobStore: BlobStore
    @ObservedObject var viewModel: PickerViewModel
    let canQuickShare: Bool

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                EmptyStateView(systemImage: "sidebar.right", title: L("No selection"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(LeafiyDesign.Spacing.m)
    }

    @ViewBuilder private func content(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
            header(for: item)
            Divider()
            detail(for: item)
            Spacer(minLength: 0)
            actions(for: item)
        }
    }

    private func header(for item: ClipboardItem) -> some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            Text(item.type.fifiLabel)
                .font(.headline)
            if item.isSensitive {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
                    .help(L("Sensitive content"))
            }
            Spacer()
            if let app = item.sourceAppName {
                Text(app)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private func detail(for item: ClipboardItem) -> some View {
        switch item.type {
        case .text, .richText, .unknown:
            TextDetail(item: item, blobStore: blobStore)
        case .url:
            urlDetail(item)
        case .color:
            colorDetail(item)
        case .image:
            imageDetail(item)
        case .file:
            fileDetail(item)
        }
    }

    private func urlDetail(_ item: ClipboardItem) -> some View {
        let raw = item.contentText ?? item.previewText
        let cleaned = URLCleaner.cleaned(raw) ?? raw
        return VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xs) {
            Text(URL(string: raw)?.host ?? raw)
                .font(.callout.weight(.semibold))
            ScrollView { Text(raw).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                .frame(maxHeight: 120)
            if cleaned != raw {
                Text(L("Without tracking:"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(cleaned)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func colorDetail(_ item: ClipboardItem) -> some View {
        let raw = item.contentText ?? item.previewText
        let color = ColorValue(hexString: raw)
        return VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.s) {
            RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control)
                .fill(swatchColor(color))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control).strokeBorder(.quaternary))
            if let color {
                colorRow("HEX", color.hexString)
                colorRow("RGB", color.rgbString)
                colorRow("HSL", color.hslString)
            } else {
                Text(raw).font(.callout.monospaced())
            }
        }
    }

    private func colorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
            Spacer()
        }
    }

    private func swatchColor(_ color: ColorValue?) -> Color {
        guard let color else { return .clear }
        return Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    private func imageDetail(_ item: ClipboardItem) -> some View {
        ImageDetail(item: item, blobStore: blobStore)
    }

    private func fileDetail(_ item: ClipboardItem) -> some View {
        let paths = PasteboardWriter.filePaths(for: item)
        return VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xs) {
            ForEach(paths, id: \.self) { path in
                HStack(spacing: LeafiyDesign.Spacing.xs) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable().frame(width: 20, height: 20)
                    Text(path)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder private func actions(for item: ClipboardItem) -> some View {
        VStack(spacing: LeafiyDesign.Spacing.xs) {
            Button {
                viewModel.copyToClipboard(item: item)
            } label: {
                Label(L("Send to Clipboard"), systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
            }
            Button {
                viewModel.performQuickAction(.quickShare, item: item)
            } label: {
                Label(L("Quick Share"), systemImage: "link").frame(maxWidth: .infinity)
            }
            .disabled(!canQuickShare)
            switch item.type {
            case .url:
                Button { viewModel.performQuickAction(.openURL, item: item) } label: {
                    Label(L("Open URL"), systemImage: "safari").frame(maxWidth: .infinity)
                }
                Button { viewModel.performQuickAction(.copyCleanURL, item: item) } label: {
                    Label(L("Copy Without Tracking"), systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
            case .color:
                HStack {
                    Button("HEX") { viewModel.performQuickAction(.copyColorHex, item: item) }
                    Button("RGB") { viewModel.performQuickAction(.copyColorRGB, item: item) }
                    Button("HSL") { viewModel.performQuickAction(.copyColorHSL, item: item) }
                }
            case .file:
                Button { viewModel.performQuickAction(.revealInFinder, item: item) } label: {
                    Label(L("Reveal in Finder"), systemImage: "folder").frame(maxWidth: .infinity)
                }
                Button { viewModel.performQuickAction(.quickLook, item: item) } label: {
                    Label(L("Quick Look"), systemImage: "eye").frame(maxWidth: .infinity)
                }
            default:
                Button { viewModel.performQuickAction(.copyPlainText, item: item) } label: {
                    Label(L("Copy as Plain Text"), systemImage: "text.alignleft").frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Loads and displays the full text of a text item (reading a blob if needed).
private struct TextDetail: View {
    let item: ClipboardItem
    let blobStore: BlobStore
    @State private var text: String = ""

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? item.previewText : text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id) { load() }
    }

    private func load() {
        if let blobPath = item.blobPath, let data = try? blobStore.data(atRelativePath: blobPath),
           let value = String(data: data, encoding: .utf8) {
            text = value
        } else {
            text = item.contentText ?? item.previewText
        }
    }
}

/// Loads and displays the full image of an image item.
private struct ImageDetail: View {
    let item: ClipboardItem
    let blobStore: BlobStore
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xs) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 240)
            } else {
                RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control).fill(.quaternary).frame(height: 160)
            }
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .task(id: item.id) { load() }
    }

    /// Localized "Image" label plus pixel dimensions when the capture recorded
    /// them, replacing the English preview text baked in at capture time.
    private var caption: String {
        guard let json = item.metadataJSON, let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let width = Self.dimension(object["width"]), let height = Self.dimension(object["height"]),
              width > 0, height > 0 else {
            return L("Image")
        }
        return "\(L("Image")) \(width)×\(height)"
    }

    private static func dimension(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let doubleValue = value as? Double { return Int(doubleValue) }
        if let stringValue = value as? String { return Int(stringValue) }
        return nil
    }

    private func load() {
        guard let blobPath = item.blobPath, let data = try? blobStore.data(atRelativePath: blobPath) else {
            image = nil
            return
        }
        image = NSImage(data: data)
    }
}
