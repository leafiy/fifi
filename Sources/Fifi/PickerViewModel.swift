import Combine
import Foundation
import FifiCore

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

    let pageSize = 50
    var onActivate: ((ClipboardItem) -> Void)?

    private let historyService: HistoryService
    private var searchWorkItem: DispatchWorkItem?
    private var isLoading = false
    private var isResettingQuery = false

    init(historyService: HistoryService) {
        self.historyService = historyService
    }

    func reload() {
        searchWorkItem?.cancel()
        isResettingQuery = true
        query = ""
        isResettingQuery = false
        loadFirstPage(for: "")
    }

    func loadMore() {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        let offset = items.count
        let page = loadPage(query: query, offset: offset)
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
        guard items.indices.contains(selectedIndex) else { return }
        let item = items[selectedIndex]
        historyService.delete(item: item)
        items.remove(at: selectedIndex)
        clampSelection()
    }

    func togglePinSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        let index = selectedIndex
        historyService.togglePin(item: items[index])
        items[index].isPinned.toggle()
        selectedIndex = index
        clampSelection()
    }

    func activateSelected() {
        guard items.indices.contains(selectedIndex) else { return }
        activate(item: items[selectedIndex])
    }

    func activate(item: ClipboardItem) {
        onActivate?(item)
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
        let page = loadPage(query: query, offset: 0)
        items = page
        selectedIndex = page.isEmpty ? -1 : 0
        canLoadMore = page.count == pageSize
        isLoading = false
        clampSelection()
    }

    private func loadPage(query: String, offset: Int) -> [ClipboardItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return historyService.recent(limit: pageSize, offset: offset)
        }
        return historyService.search(trimmedQuery, limit: pageSize, offset: offset)
    }

    private func clampSelection() {
        if items.isEmpty {
            selectedIndex = -1
        } else {
            selectedIndex = min(max(selectedIndex, 0), items.count - 1)
        }
    }
}
