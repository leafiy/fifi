import Combine
import Foundation
import FifiCore

enum PickerViewMode: String, CaseIterable, Identifiable {
    case all, favorites, recent, frequent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return L("All")
        case .favorites: return L("Favorites")
        case .recent: return L("Recent")
        case .frequent: return L("Frequent")
        }
    }
}

enum PickerDateRange: String, CaseIterable, Identifiable {
    case any, today, last7Days, last30Days
    var id: String { rawValue }
    var label: String {
        switch self {
        case .any: return L("Any date")
        case .today: return L("Today")
        case .last7Days: return L("Last 7 days")
        case .last30Days: return L("Last 30 days")
        }
    }

    var since: Date? {
        let calendar = Calendar.current
        switch self {
        case .any: return nil
        case .today: return calendar.startOfDay(for: Date())
        case .last7Days: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .last30Days: return calendar.date(byAdding: .day, value: -30, to: Date())
        }
    }
}

enum PickerQuickAction {
    case copyPlainText
    case copyColorHex, copyColorRGB, copyColorHSL
    case copyCleanURL, openURL
    case revealInFinder, quickLook
}

@MainActor
final class PickerViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard !isResettingQuery, query != oldValue else { return }
            scheduleSearch()
        }
    }
    @Published var items: [ClipboardItem] = []
    @Published var selectedIndex = -1
    @Published var focusToken = 0
    @Published var canLoadMore = false
    @Published var listRevision = 0

    // Filter state — changes reload immediately (no debounce).
    @Published var viewMode: PickerViewMode = .all { didSet { reloadIfChanged(oldValue != viewMode) } }
    @Published var selectedTypes: Set<ClipItemType> = [] { didSet { reloadIfChanged(oldValue != selectedTypes) } }
    @Published var sourceAppBundleID: String? = nil { didSet { reloadIfChanged(oldValue != sourceAppBundleID) } }
    @Published var dateRange: PickerDateRange = .any { didSet { reloadIfChanged(oldValue != dateRange) } }
    @Published var isRegex = false { didSet { reloadIfChanged(oldValue != isRegex) } }
    @Published var sourceApps: [SourceAppSummary] = []

    // Set by the controller from settings before each show.
    var sortOrder: HistorySortOrder = .recency
    var fuzzyRanking = false
    var numberShortcuts = true

    let pageSize = 50
    var onActivate: ((ClipboardItem) -> Void)?
    var onCopyToClipboard: ((ClipboardItem) -> Void)?
    var onQuickAction: ((PickerQuickAction, ClipboardItem) -> Void)?

    private let historyService: HistoryService
    private var searchWorkItem: DispatchWorkItem?
    private var isLoading = false
    private var isResettingQuery = false
    private var memoryCount = 0

    init(historyService: HistoryService) {
        self.historyService = historyService
    }

    var selectedItem: ClipboardItem? {
        items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    func reload() {
        searchWorkItem?.cancel()
        sourceApps = historyService.distinctSourceApps()
        loadFirstPage(for: query)
    }

    /// Resets all filters and query to defaults, then reloads.
    func resetFilters() {
        isResettingQuery = true
        query = ""
        isResettingQuery = false
        viewMode = .all
        selectedTypes = []
        sourceAppBundleID = nil
        dateRange = .any
        isRegex = false
        reload()
    }

    private func reloadIfChanged(_ changed: Bool) {
        guard changed else { return }
        loadFirstPage(for: query)
    }

    private func currentQuery(text: String) -> HistoryQuery {
        var filter = HistoryFilter()
        filter.types = selectedTypes
        if let bundleID = sourceAppBundleID { filter.sourceAppBundleIDs = [bundleID] }
        filter.since = dateRange.since
        filter.pinnedOnly = viewMode == .favorites
        if viewMode == .recent, filter.since == nil {
            filter.since = Calendar.current.date(byAdding: .day, value: -7, to: Date())
        }
        if viewMode == .frequent { filter.minUseCount = 1 }

        let sort: HistorySortOrder = viewMode == .frequent ? .mostUsed : sortOrder
        return HistoryQuery(
            text: text,
            isRegex: isRegex,
            filter: filter,
            sort: sort,
            fuzzyRanking: fuzzyRanking
        )
    }

    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        let query = currentQuery(text: self.query)
        let diskOffset = items.count - memoryCount
        let page = historyService.items(matching: query, limit: pageSize, offset: diskOffset)
        items.append(contentsOf: page)
        canLoadMore = page.count == pageSize
        isLoading = false
        clampSelection()
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else {
            selectedIndex = -1
            return
        }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item: item)
    }

    func delete(item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard historyService.delete(item: item) else {
            reload()
            return
        }
        if HistoryService.isMemoryItem(item.id) { memoryCount = max(0, memoryCount - 1) }
        items.remove(at: index)
        clampSelection()
    }

    func deleteItem(id: Int64) {
        guard let item = items.first(where: { $0.id == id }) else {
            reload()
            return
        }
        delete(item: item)
    }

    func togglePinSelected() {
        guard let item = selectedItem, !HistoryService.isMemoryItem(item.id) else { return }
        let index = selectedIndex
        historyService.togglePin(item: item)
        items[index].isPinned.toggle()
        selectedIndex = index
        clampSelection()
    }

    func activateSelected() {
        guard let item = selectedItem else { return }
        activate(item: item)
    }

    func activate(item: ClipboardItem) {
        onActivate?(item)
    }

    func copyToClipboard(item: ClipboardItem) {
        onCopyToClipboard?(item)
    }

    func copyToClipboard(id: Int64) {
        guard let item = items.first(where: { $0.id == id }) else {
            reload()
            return
        }
        copyToClipboard(item: item)
    }

    func performQuickAction(_ action: PickerQuickAction, item: ClipboardItem) {
        onQuickAction?(action, item)
    }

    func copyShortcutItem(at index: Int) {
        guard numberShortcuts, (0..<10).contains(index), items.indices.contains(index) else { return }
        copyToClipboard(item: items[index])
    }

    private func scheduleSearch() {
        searchWorkItem?.cancel()
        canLoadMore = false
        let expectedQuery = query
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.loadFirstPage(for: expectedQuery)
            }
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    private func loadFirstPage(for query: String) {
        guard query == self.query else { return }
        isLoading = true
        let historyQuery = currentQuery(text: query)
        let memoryItems = historyService.memoryItems(matching: historyQuery)
        let diskItems = historyService.items(matching: historyQuery, limit: pageSize, offset: 0)
        memoryCount = memoryItems.count
        items = memoryItems + diskItems
        selectedIndex = items.isEmpty ? -1 : 0
        canLoadMore = diskItems.count == pageSize
        isLoading = false
        listRevision += 1
        clampSelection()
    }

    private func clampSelection() {
        if items.isEmpty {
            selectedIndex = -1
        } else {
            selectedIndex = min(max(selectedIndex, 0), items.count - 1)
        }
    }
}
