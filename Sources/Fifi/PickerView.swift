import AppKit
import FifiCore
import LeafiyUI
import SwiftUI

struct PickerView: View {
    static let previewPanelWidth: CGFloat = 300

    @ObservedObject var viewModel: PickerViewModel
    @ObservedObject var settingsStore: SettingsStore
    let thumbnailLoader: ThumbnailLoader
    let blobStore: BlobStore

    @FocusState private var searchFocused: Bool

    private var density: RowDensity { settingsStore.settings.rowDensity }
    private var showPreview: Bool { settingsStore.settings.showPreviewPanel }
    private var showFilters: Bool { settingsStore.settings.showPickerFilters }
    private var showSourceApp: Bool { settingsStore.settings.showSourceApp }
    private var listWidth: CGFloat { CGFloat(settingsStore.settings.pickerWidth) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                filterBar
                Divider()
                itemList
                footer
            }
            .frame(width: showPreview ? listWidth : nil)
            .frame(maxWidth: showPreview ? nil : .infinity, maxHeight: .infinity)

            if showPreview {
                Divider()
                PreviewPanel(
                    item: viewModel.selectedItem,
                    blobStore: blobStore,
                    viewModel: viewModel,
                    canQuickShare: settingsStore.settings.quickShare.isConfigured
                )
                    .frame(width: Self.previewPanelWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque window background to match daisy/eddy; the panel window
        // itself is transparent, so this fill is the visible surface. With
        // window transparency on, a frosted desktop backdrop sits underneath
        // and the fill thins out by the blur strength — the effect view
        // itself must stay at full alpha (NSVisualEffectView does not
        // composite reliably with a fractional alphaValue), so the fill's
        // remaining coverage is what meters the blur.
        .background {
            ZStack {
                if settingsStore.settings.windowOpacityEnabled {
                    WindowBlurBackdrop()
                }
                Color(nsColor: .windowBackgroundColor)
                    .opacity(1 - settingsStore.settings.windowBlurIntensity)
            }
            .ignoresSafeArea()
        }
        .onAppear(perform: handleAppear)
        .onChange(of: showFilters) {
            clearHiddenFiltersIfNeeded()
        }
        .onChange(of: viewModel.focusToken) {
            focusSearch()
        }
    }

    private var searchBar: some View {
        HStack(spacing: LeafiyDesign.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(viewModel.isRegex ? L("Search (regex)") : L("Search clipboard"), text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            Toggle(isOn: $viewModel.isRegex) {
                Text(".*")
                    .font(.caption.monospaced())
            }
            .toggleStyle(.button)
            .help(L("Regex search"))
        }
        .font(.body)
        .padding(.horizontal, LeafiyDesign.Spacing.m)
        .padding(.vertical, LeafiyDesign.Spacing.s)
    }

    private var filterBar: some View {
        VStack(spacing: LeafiyDesign.Spacing.xs) {
            Picker(L("View"), selection: $viewModel.viewMode) {
                ForEach(PickerViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if showFilters {
                HStack(spacing: LeafiyDesign.Spacing.xs) {
                    typeMenu
                    appMenu
                    dateMenu
                    Spacer()
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, LeafiyDesign.Spacing.m)
        .padding(.bottom, LeafiyDesign.Spacing.xs)
    }

    private var typeMenu: some View {
        Menu {
            Button {
                viewModel.selectedTypes = []
            } label: {
                Label(L("All types"), systemImage: viewModel.selectedTypes.isEmpty ? "checkmark" : "")
            }
            Divider()
            ForEach(ClipItemType.allCases, id: \.self) { type in
                Button {
                    toggleType(type)
                } label: {
                    Label(type.fifiLabel, systemImage: viewModel.selectedTypes.contains(type) ? "checkmark" : "")
                }
            }
        } label: {
            Label(typeMenuLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
    }

    private var appMenu: some View {
        Menu {
            Button {
                viewModel.sourceAppBundleID = nil
            } label: {
                Label(L("All apps"), systemImage: viewModel.sourceAppBundleID == nil ? "checkmark" : "")
            }
            if !viewModel.sourceApps.isEmpty {
                Divider()
                ForEach(viewModel.sourceApps) { app in
                    Button {
                        viewModel.sourceAppBundleID = app.bundleID
                    } label: {
                        Label(
                            app.appName ?? app.bundleID,
                            systemImage: viewModel.sourceAppBundleID == app.bundleID ? "checkmark" : ""
                        )
                    }
                }
            }
        } label: {
            Label(appMenuLabel, systemImage: "app.badge")
        }
        .fixedSize()
    }

    private var dateMenu: some View {
        Menu {
            ForEach(PickerDateRange.allCases) { range in
                Button {
                    viewModel.dateRange = range
                } label: {
                    Label(range.label, systemImage: viewModel.dateRange == range ? "checkmark" : "")
                }
            }
        } label: {
            Label(viewModel.dateRange.label, systemImage: "calendar")
        }
        .fixedSize()
    }

    private var typeMenuLabel: String {
        switch viewModel.selectedTypes.count {
        case 0: return L("Type")
        case 1: return viewModel.selectedTypes.first!.fifiLabel
        default: return String(format: L("%d types"), viewModel.selectedTypes.count)
        }
    }

    private var appMenuLabel: String {
        guard let bundleID = viewModel.sourceAppBundleID else { return L("App") }
        return viewModel.sourceApps.first { $0.bundleID == bundleID }?.appName ?? L("App")
    }

    private func toggleType(_ type: ClipItemType) {
        if viewModel.selectedTypes.contains(type) {
            viewModel.selectedTypes.remove(type)
        } else {
            viewModel.selectedTypes.insert(type)
        }
    }

    @ViewBuilder private var itemList: some View {
        if viewModel.items.isEmpty {
            EmptyStateView(
                systemImage: "clipboard",
                title: viewModel.query.isEmpty ? L("No clipboard history") : L("No matches")
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
                                density: density,
                                showShortcut: settingsStore.settings.numberShortcuts,
                                showSourceApp: showSourceApp,
                                canQuickShare: settingsStore.settings.quickShare.isConfigured,
                                thumbnailLoader: thumbnailLoader,
                                onActivate: { viewModel.activate(item: row.item) },
                                onCopyToClipboard: { viewModel.copyToClipboard(item: row.item) },
                                onTogglePin: { viewModel.togglePin(item: row.item) },
                                onDelete: { viewModel.deleteItem(id: row.item.id) },
                                onQuickAction: { viewModel.performQuickAction($0, item: row.item) }
                            )
                            .id(row.item.id)
                            .onHover { hovering in
                                if hovering { viewModel.hoverSelect(index: row.index) }
                            }
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
                    guard !viewModel.consumeHoverSelection() else { return }
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
            Text(String(format: viewModel.items.count == 1 ? L("%d item") : L("%d items"), viewModel.items.count))
            Spacer()
            Text(settingsStore.settings.numberShortcuts ? L("↩ paste · ⌘1-0 copy") : L("↩ paste"))
        }
    }

    private var rowModels: [PickerRowModel] {
        viewModel.items.enumerated().map { PickerRowModel(index: $0.offset, item: $0.element) }
    }

    private func handleAppear() {
        clearHiddenFiltersIfNeeded()
        focusSearch()
    }

    private func focusSearch() {
        DispatchQueue.main.async {
            searchFocused = true
        }
    }

    private func clearHiddenFiltersIfNeeded() {
        guard !showFilters else { return }
        viewModel.selectedTypes = []
        viewModel.sourceAppBundleID = nil
        viewModel.dateRange = .any
    }
}

/// Frosted desktop backdrop for the translucent picker. Blends the blurred
/// content behind the panel with the window fill layered on top; kept at
/// full alpha and clipped by the panel's rounded `clipShape` like any other
/// SwiftUI layer.
private struct WindowBlurBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        // The panel is non-activating and never becomes main; .active keeps
        // the desktop sample live regardless of window state.
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PickerRowModel: Identifiable {
    let index: Int
    let item: ClipboardItem
    var id: Int64 { item.id }
}

extension ClipItemType {
    var fifiLabel: String {
        switch self {
        case .text: return L("Text")
        case .richText: return L("Rich Text")
        case .url: return L("URLs")
        case .image: return L("Images")
        case .color: return L("Colors")
        case .file: return L("Files")
        case .unknown: return L("Other")
        }
    }
}
