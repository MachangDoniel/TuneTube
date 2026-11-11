import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var shelves: [Shelf] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private var searchMemoryCache: [String: [Shelf]] = [:]

    /// Debounced to 450ms so typing doesn't spam requests, with instant in-memory cache lookup.
    func queryChanged() {
        searchTask?.cancel()
        errorMessage = nil
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
        errorMessage = nil
        query = text
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let cached = searchMemoryCache[key] {
            shelves = cached
            isSearching = false
            return
        }
        searchTask = Task { await run(text) }
    }

    func clear() {
        searchTask?.cancel()
        errorMessage = nil
        query = ""
        shelves = []
        isSearching = false
    }

    /// Region or language changed. Every memoised result was for the old
    /// `gl`/`hl`, so drop them and re-run whatever is in the field.
    func localeDidChange() {
        searchTask?.cancel()
        errorMessage = nil
        searchMemoryCache.removeAll()
        shelves = []
        isSearching = false

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return }
        searchTask = Task { await run(text) }
    }

    private func run(_ text: String) async {
        let key = text.lowercased()
        isSearching = true
        defer {
            if !Task.isCancelled { isSearching = false }
        }
        do {
            let results = try await APIClient.shared.search(text)
            guard !Task.isCancelled else { return }
            searchMemoryCache[key] = results
            shelves = results
        } catch {
            guard !Task.isCancelled else { return }
            shelves = []
            errorMessage = error.localizedDescription
        }
    }
}
