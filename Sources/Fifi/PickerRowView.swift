import AppKit
import FifiCore
import LeafiyUI
import LeafiyUICore
import SwiftUI

struct PickerRowView: View {
    private enum Metrics {
        static let shortcutBadgeWidth: CGFloat = 30
        static let rowActionsWidth: CGFloat = 68
        static let rowActionSize: CGFloat = 32
        static let thumbnailSize: CGFloat = LeafiyDesign.Size.rowIcon
        static let colorSwatchSize: CGFloat = LeafiyDesign.Spacing.l
    }

    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let density: RowDensity
    let showShortcut: Bool
    let showSourceApp: Bool
    let showItemSize: Bool
    let showItemTime: Bool
    let showImageResolution: Bool
    let canQuickShare: Bool
    let thumbnailLoader: ThumbnailLoader
    let onActivate: () -> Void
    let onCopyToClipboard: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onQuickAction: (PickerQuickAction) -> Void

    private var textLineLimit: Int { density == .compact ? 1 : 2 }
    private var verticalPadding: CGFloat { density == .compact ? LeafiyDesign.Spacing.xs : LeafiyDesign.Spacing.s }

    var body: some View {
        HStack(alignment: .center, spacing: LeafiyDesign.Spacing.s) {
            if showShortcut { shortcutBadge }
            contentColumn
            rowActions
        }
        .padding(.leading, showShortcut ? LeafiyDesign.Spacing.m : LeafiyDesign.Spacing.s)
        .padding(.trailing, LeafiyDesign.Spacing.s)
        .padding(.vertical, verticalPadding)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: LeafiyDesign.Radius.control)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(.horizontal, LeafiyDesign.Spacing.xs)
                    .padding(.vertical, LeafiyDesign.Spacing.xxs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onActivate)
        .contextMenu { contextMenu }
    }

    @ViewBuilder private var contextMenu: some View {
        Button(L("Send to Clipboard"), action: onCopyToClipboard)
        Button(L("Quick Share")) { onQuickAction(.quickShare) }
            .disabled(!canQuickShare)
        Button(L("Copy as Plain Text")) { onQuickAction(.copyPlainText) }
        Button(item.isPinned ? L("Remove from Favorites") : L("Add to Favorites"), action: onTogglePin)
            .disabled(HistoryService.isMemoryItem(item.id))
        switch item.type {
        case .color:
            Button(L("Copy as HEX")) { onQuickAction(.copyColorHex) }
            Button(L("Copy as RGB")) { onQuickAction(.copyColorRGB) }
            Button(L("Copy as HSL")) { onQuickAction(.copyColorHSL) }
        case .url:
            Button(L("Open URL")) { onQuickAction(.openURL) }
            Button(L("Copy Without Tracking")) { onQuickAction(.copyCleanURL) }
        case .file:
            Button(L("Reveal in Finder")) { onQuickAction(.revealInFinder) }
            Button(L("Quick Look")) { onQuickAction(.quickLook) }
        default:
            EmptyView()
        }
        Divider()
        Button(L("Delete"), role: .destructive, action: onDelete)
    }

    private var contentColumn: some View {
        Group {
            if item.type == .image {
                imagePreview
            } else {
                VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xs) {
                    rowPreview
                    if density != .compact && hasMetadataLine { metadataLine }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var rowPreview: some View {
        switch item.type {
        case .text, .richText: textPreview
        case .url: urlPreview
        case .image: imagePreview
        case .color: colorPreview
        case .file: filePreview
        case .unknown: unknownPreview
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
        Text(item.previewText.isEmpty ? L("Empty text") : item.previewText)
            .font(PickerSymbolFont.callout)
            .lineLimit(textLineLimit)
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
            ThumbnailView(item: item, loader: thumbnailLoader, size: Metrics.thumbnailSize)
            VStack(alignment: .leading, spacing: LeafiyDesign.Spacing.xxs) {
                Text(L("Image"))
                    .font(.callout)
                    .lineLimit(1)
                if let imageDetailText {
                    Text(imageDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if density != .compact && hasMetadataLine { metadataLine }
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
                Text(fileDetailText)
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

    /// Whether the details line has anything to render: state indicators
    /// (pin, memory-only) always count; the text details only when their
    /// toggles leave something visible. An empty line costs zero pixels.
    private var hasMetadataLine: Bool {
        item.isPinned || HistoryService.isMemoryItem(item.id) || !metadataText.isEmpty
    }

    private var metadataLine: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if HistoryService.isMemoryItem(item.id) {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !metadataText.isEmpty {
                Text(metadataText)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowActions: some View {
        HStack(spacing: LeafiyDesign.Spacing.xs) {
            RowActionButton(
                systemImage: "doc.on.clipboard",
                help: L("Send to Clipboard"),
                size: Metrics.rowActionSize,
                action: onCopyToClipboard
            )
            RowActionButton(
                systemImage: "trash",
                help: L("Delete"),
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

    private var urlText: String { item.contentText ?? item.previewText }

    private var urlDomain: String {
        if let domain = metadata["domain"] as? String, !domain.isEmpty { return domain }
        return URL(string: urlText)?.host ?? urlText
    }

    private var imageDimensions: String? {
        guard let width = metadataInt("width"), let height = metadataInt("height") else { return nil }
        return "\(width) × \(height)"
    }

    private var imageDetailText: String? {
        let detail = [
            showImageResolution ? imageDimensions : nil,
            showItemSize ? fileSizeText : nil,
        ].compactMap(\.self).joined(separator: " · ")
        return detail.isEmpty ? nil : detail
    }

    private var fileSizeText: String? {
        guard item.byteSize > 0 else { return nil }
        let megabytes = Double(item.byteSize) / 1_048_576
        let rounded = item.byteSize > 0 ? max(megabytes, 0.1) : 0
        return String(format: "%.1fm", rounded)
    }

    private var textCharacterCount: Int {
        (item.contentText ?? item.previewText).count
    }

    private var itemMetricText: String? {
        switch item.type {
        case .text, .richText:
            return String(format: L("%d chars"), textCharacterCount)
        default:
            return nil
        }
    }

    private var metadataText: String {
        var parts: [String] = []
        if showItemSize, let itemMetricText { parts.append(itemMetricText) }
        if showSourceApp { parts.append(item.sourceAppName ?? L("Unknown")) }
        if showItemTime { parts.append(relativeUpdatedAt) }
        return parts.joined(separator: " · ")
    }

    private var colorText: String { item.contentText ?? item.previewText }

    private var colorSwatch: Color {
        guard let components = ClipboardClassifier.hexColorComponents(colorText) else { return .clear }
        return Color(red: components.r, green: components.g, blue: components.b, opacity: components.a)
    }

    private var filePath: String {
        item.fileReference?.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? item.previewText
    }

    private var fileName: String {
        let last = URL(fileURLWithPath: filePath).lastPathComponent
        return last.isEmpty ? filePath : last
    }

    private var fileDetailText: String {
        [filePath, showItemSize ? fileSizeText : nil].compactMap(\.self).joined(separator: " · ")
    }

    private var fileIcon: NSImage { NSWorkspace.shared.icon(forFile: filePath) }

    private var unknownLabel: String {
        if let first = item.previewText
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map(String.init), !first.isEmpty {
            return first
        }
        return L("Unknown item")
    }

    private func metadataInt(_ key: String) -> Int? {
        if let value = metadata[key] as? Int { return value }
        if let value = metadata[key] as? Double { return Int(value) }
        if let value = metadata[key] as? String { return Int(value) }
        return nil
    }

    /// Relative timestamp resolved against the app's selected language rather
    /// than only the system locale, so it matches the rest of the picker.
    private var relativeUpdatedAt: String {
        let formatter = Self.relativeDateFormatter
        formatter.locale = Locale(identifier: LeafiyLocalization.resolvedCode())
        return formatter.localizedString(for: item.updatedAt, relativeTo: Date())
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter
    }()
}

struct RowActionButton: NSViewRepresentable {
    let systemImage: String
    let help: String
    let size: CGFloat
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

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
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performAction(_ sender: NSButton) { action() }
    }
}

/// Callout font whose fallback cascade includes an installed Nerd Font, so
/// private-use-area glyphs in clipboard text render instead of boxed glyphs.
@MainActor
enum PickerSymbolFont {
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
