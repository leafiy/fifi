import AppKit
import FifiCore
import LeafiyUI
import SwiftUI

struct PickerView: View {
    private enum Metrics {
        static let pickerWidth: CGFloat = 420
        static let pickerHeight: CGFloat = 480
        static let shortcutBadgeWidth: CGFloat = 30
        static let rowActionsWidth: CGFloat = 68
        static let rowActionSize: CGFloat = 32
        static let colorSwatchSize: CGFloat = LeafiyDesign.Spacing.l
    }

    @ObservedObject var viewModel: PickerViewModel
    let thumbnailLoader: ThumbnailLoader

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            itemList
            footer
        }
        .frame(width: Metrics.pickerWidth, height: Metrics.pickerHeight)
        .background(.regularMaterial)
        .onAppear(perform: focusSearch)
        .onChange(of: viewModel.focusToken) {
            focusSearch()
        }
    }

    private var searchBar: some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .font(.body)
        .padding(.horizontal, LeafiyDesign.Spacing.m)
        .padding(.vertical, LeafiyDesign.Spacing.s)
    }

    @ViewBuilder private var itemList: some View {
        if viewModel.items.isEmpty {
            EmptyStateView(
                systemImage: "clipboard",
                title: viewModel.query.isEmpty ? "No clipboard history" : "No matches"
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
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
                    .padding(.vertical, LeafiyDesign.Spacing.xs)
                }
                .id(viewModel.listRevision)
                .onChange(of: viewModel.selectedIndex) { _, index in
                    guard viewModel.items.indices.contains(index) else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(viewModel.items[index].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        FooterBar {
            Text("\(viewModel.items.count) item\(viewModel.items.count == 1 ? "" : "s")")
            Spacer()
            Text("↩ paste · ⌘1-0 copy")
        }
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
    private enum Metrics {
        static let shortcutBadgeWidth: CGFloat = 30
        static let rowActionsWidth: CGFloat = 68
        static let rowActionSize: CGFloat = 32
        static let colorSwatchSize: CGFloat = LeafiyDesign.Spacing.l
    }

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
        HStack(alignment: .center, spacing: LeafiyDesign.Spacing.s) {
            shortcutBadge
            contentColumn
            rowActions
        }
        .padding(.leading, LeafiyDesign.Spacing.m)
        .padding(.trailing, LeafiyDesign.Spacing.s)
        .padding(.vertical, LeafiyDesign.Spacing.s)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(.horizontal, LeafiyDesign.Spacing.xs)
                    .padding(.vertical, LeafiyDesign.Spacing.xxs)
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
                VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xs) {
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
        HStack(spacing: LeafiyDesign.Spacing.xxs) {
            Image(systemName: "command")
                .font(.caption2.weight(.medium))
            Text(shortcutLabel ?? "")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(shortcutLabel == nil ? Color.clear : Color.secondary)
        .frame(width: Metrics.shortcutBadgeWidth, alignment: .leading)
    }

    private var shortcutLabel: String? {
        guard index < 10 else { return nil }
        return index == 9 ? "0" : String(index + 1)
    }

    private var textPreview: some View {
        Text(item.previewText.isEmpty ? "Empty text" : item.previewText)
            .font(PickerSymbolFont.callout)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var urlPreview: some View {
        VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
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
        HStack(alignment: .center, spacing: LeafiyDesign.Spacing.s) {
            ThumbnailView(item: item, loader: thumbnailLoader)
                .frame(width: LeafiyDesign.Size.rowIcon, height: LeafiyDesign.Size.rowIcon)
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
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
        HStack(spacing: LeafiyDesign.Spacing.s) {
            RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control)
                .fill(colorSwatch)
                .frame(width: Metrics.colorSwatchSize, height: Metrics.colorSwatchSize)
                .overlay(RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control).strokeBorder(.quaternary))
            Text(colorText)
                .font(.callout.monospaced())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filePreview: some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: LeafiyDesign.Size.rowIcon, height: LeafiyDesign.Size.rowIcon)
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(fileName)
                    .font(PickerSymbolFont.callout)
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
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Image(systemName: "questionmark.square")
                .foregroundStyle(.secondary)
            Text(unknownLabel)
                .font(PickerSymbolFont.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metadataLine: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(item.sourceAppName ?? "Unknown")
                .lineLimit(1)
            Text("·")
            Text(Self.relativeDateFormatter.localizedString(for: item.updatedAt, relativeTo: Date()))
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowActions: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            RowActionButton(
                systemImage: "doc.on.clipboard",
                help: "Send to Clipboard",
                size: Metrics.rowActionSize,
                action: onCopyToClipboard
            )
            RowActionButton(
                systemImage: "trash",
                help: "Delete",
                size: Metrics.rowActionSize,
                action: onDelete
            )
        }
        .frame(width: Metrics.rowActionsWidth, alignment: .trailing)
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
    let size: CGFloat
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: systemImage, accessibilityDescription: help) ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.performAction(_:))
        )
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.toolTip = help
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
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

/// Callout font whose fallback cascade includes an installed Nerd Font, so
/// private-use-area glyphs in clipboard text (terminal prompts, powerline
/// segments) render instead of the LastResort boxed question marks — PUA
/// codepoints belong to no script, so the system cascade never reaches
/// user-installed fonts for them on its own.
///
/// Kept local to fifi so the picker builds against any leafiy-ui revision.
@MainActor
private enum PickerSymbolFont {
    static let callout: Font = {
        let base = NSFont.preferredFont(forTextStyle: .callout, options: [:])
        let families = NSFontManager.shared.availableFontFamilies
        let preferred = ["Symbols Nerd Font Mono", "Symbols Nerd Font"]
        let family = preferred.first(where: families.contains)
            ?? families.first { $0.contains("Nerd Font") }
        guard let family else {
            return Font(base as CTFont)
        }
        let fallback = NSFontDescriptor(fontAttributes: [.family: family])
        let descriptor = base.fontDescriptor.addingAttributes([.cascadeList: [fallback]])
        return Font((NSFont(descriptor: descriptor, size: base.pointSize) ?? base) as CTFont)
    }()
}
