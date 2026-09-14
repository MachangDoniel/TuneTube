import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var shelves: [Shelf] = []
    private(set) var isSearching = false
    private(set) var config: RemoteConfig = .fallback

    private var searchTask: Task<Void, Never>?
    private var searchMemoryCache: [String: [Shelf]] = [:]

    func loadConfig() async {
        if let c = try? await APIClient.shared.config() { config = c }
    }

    /// Debounced to 450ms so typing doesn't spam requests, with instant in-memory cache lookup.
    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            shelves = []
            isSearching = false
            return
        }

        let key = text.lowercased()
        if let cached = searchMemoryCache[key] {
            shelves = cached
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await run(text)
        }
    }

    func searchNow(_ text: String) {
        searchTask?.cancel()
        query = text
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = searchMemoryCache[key] {
            shelves = cached
            isSearching = false
            return
        }
        Task { await run(text) }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        shelves = []
        isSearching = false
    }

    private func run(_ text: String) async {
        let key = text.lowercased()
        isSearching = true
        defer { isSearching = false }
        do {
            let results = try await APIClient.shared.search(text)
            searchMemoryCache[key] = results
            if !results.isEmpty || shelves.isEmpty {
                shelves = results
            }
        } catch {
            if shelves.isEmpty, let fallback = await APIClient.shared.lastLoadedSearch() {
                shelves = fallback
            }
        }
    }
}
