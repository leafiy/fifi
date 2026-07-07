import AppKit
import FifiCore
import SwiftUI

struct PickerView: View {
    @ObservedObject var viewModel: PickerViewModel
    let thumbnailLoader: ThumbnailLoader

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            itemList
            Divider()
            footer
        }
        .frame(width: 420, height: 480)
        .background(.regularMaterial)
        .onAppear(perform: focusSearch)
        .onChange(of: viewModel.focusToken) { _ in
            focusSearch()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .font(.body)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var itemList: some View {
        if viewModel.items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rowModels) { row in
                            PickerRowView(
                                item: row.item,
                                index: row.index,
                                isSelected: row.index == viewModel.selectedIndex,
                                thumbnailLoader: thumbnailLoader,
                                onActivate: {
                                    viewModel.activate(item: row.item)
                                },
                                onCopyToClipboard: {
                                    viewModel.copyToClipboard(item: row.item)
                                },
                                onContextCopyToClipboard: {
                                    viewModel.copyToClipboard(id: row.item.id)
                                },
                                onDelete: {
                                    viewModel.deleteItem(id: row.item.id)
                                },
                                onContextDelete: {
                                    viewModel.deleteItem(id: row.item.id)
                                }
                            )
                                .id(row.item.id)
                                .onAppear {
                                    if row.index == viewModel.items.count - 1 {
                                        viewModel.loadMore()
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .id(viewModel.listRevision)
                .onChange(of: viewModel.selectedIndex) { index in
                    guard viewModel.items.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(viewModel.items[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(viewModel.query.isEmpty ? "No clipboard history" : "No matches")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.items.count) item\(viewModel.items.count == 1 ? "" : "s")")
            Spacer()
            Text("↩ paste · ⌘1-0 copy")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var rowModels: [PickerRowModel] {
        viewModel.items.enumerated().map { PickerRowModel(index: $0.offset, item: $0.element) }
    }

    private func focusSearch() {
        DispatchQueue.main.async {
            searchFocused = true
        }
    }
}

private struct PickerRowModel: Identifiable {
    let index: Int
    let item: ClipboardItem

    var id: Int64 { item.id }
}

private struct PickerRowView: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let thumbnailLoader: ThumbnailLoader
    let onActivate: () -> Void
    let onCopyToClipboard: () -> Void
    let onContextCopyToClipboard: () -> Void
    let onDelete: () -> Void
    let onContextDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            shortcutBadge
            contentColumn
            rowActions
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Send to Clipboard", action: onContextCopyToClipboard)
            Button("Delete", role: .destructive, action: onContextDelete)
        }
    }

    private var contentColumn: some View {
        Group {
            if item.type == .image {
                imagePreview
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    rowPreview
                    metadataLine
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var rowPreview: some View {
        switch item.type {
        case .text, .richText:
            textPreview
        case .url:
            urlPreview
        case .image:
            imagePreview
        case .color:
            colorPreview
        case .file:
            filePreview
        case .unknown:
            unknownPreview
        }
    }

    private var shortcutBadge: some View {
        HStack(spacing: 1) {
            Image(systemName: "command")
                .font(.system(size: 10, weight: .medium))
            Text(shortcutLabel ?? "")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(shortcutLabel == nil ? Color.clear : Color.secondary)
        .frame(width: 30, alignment: .leading)
    }

    private var shortcutLabel: String? {
        guard index < 10 else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    private var textPreview: some View {
        Text(item.previewText.isEmpty ? "Empty text" : item.previewText)
            .font(.callout)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var urlPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(urlDomain)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            Text(urlText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var imagePreview: some View {
        HStack(alignment: .center, spacing: 8) {
            ThumbnailView(item: item, loader: thumbnailLoader)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText.isEmpty ? "Image" : item.previewText)
                    .font(.callout)
                    .lineLimit(1)
                if let dimensions = imageDimensions {
                    Text(dimensions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                metadataLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colorPreview: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colorSwatch)
                .frame(width: 16, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
            Text(colorText)
                .font(.callout.monospaced())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filePreview: some View {
        HStack(spacing: 8) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(filePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unknownPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.square")
                .foregroundStyle(.secondary)
            Text(unknownLabel)
                .font(.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trailingInfo: some View {
        EmptyView()
    }

    private var metadataLine: some View {
        HStack(spacing: 5) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
            Text(item.sourceAppName ?? "Unknown")
                .lineLimit(1)
            Text("·")
            Text(Self.relativeDateFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(Color.secondary.opacity(0.72))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowActions: some View {
        HStack(spacing: 4) {
            RowActionButton(systemImage: "doc.on.clipboard", help: "Send to Clipboard", action: onCopyToClipboard)
            RowActionButton(systemImage: "trash", help: "Delete", action: onDelete)
        }
        .frame(width: 68, alignment: .trailing)
    }

    private var metadata: [String: Any] {
        guard let metadataJSON = item.metadataJSON,
              let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private var urlText: String {
        item.contentText ?? item.previewText
    }

    private var urlDomain: String {
        if let domain = metadata["domain"] as? String, !domain.isEmpty {
            return domain
        }
        return URL(string: urlText)?.host ?? urlText
    }

    private var imageDimensions: String? {
        guard let width = metadataInt("width"), let height = metadataInt("height") else { return nil }
        return "\(width) × \(height)"
    }

    private var colorText: String {
        item.contentText ?? item.previewText
    }

    private var colorSwatch: Color {
        guard let components = ClipboardClassifier.hexColorComponents(colorText) else { return .clear }
        return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
    }

    private var filePath: String {
        item.fileReference?.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? item.previewText
    }

    private var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent.isEmpty ? filePath : URL(fileURLWithPath: filePath).lastPathComponent
    }

    private var fileIcon: NSImage {
        NSWorkspace.shared.icon(forFile: filePath)
    }

    private var unknownLabel: String {
        if let first = item.previewText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map(String.init), !first.isEmpty {
            return first
        }
        return "Unknown item"
    }

    private func metadataInt(_ key: String) -> Int? {
        if let value = metadata[key] as? Int { return value }
        if let value = metadata[key] as? Double { return Int(value) }
        if let value = metadata[key] as? String { return Int(value) }
        return nil
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct RowActionButton: NSViewRepresentable {
    let systemImage: String
    let help: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: systemImage, accessibilityDescription: help) ?? NSImage(), target: context.coordinator, action: #selector(Coordinator.performAction(_:)))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
        nsView.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: help)
        nsView.imageScaling = .scaleProportionallyDown
        nsView.toolTip = help
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction(_ sender: NSButton) {
            action()
        }
    }
}
