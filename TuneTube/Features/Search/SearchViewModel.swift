import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    private(set) var shelves: [Shelf] = []
    private(set) var isSearching = false
    private(set) var config: RemoteConfig = .fallback

    private var searchTask: Task<Void, Never>?

    func loadConfig() async {
        if let c = try? await APIClient.shared.config() { config = c }
    }

    /// Debounced so typing doesn't fire a request per keystroke.
    func queryChanged() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            shelves = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await run(text)
        }
    }

    func searchNow(_ text: String) {
        searchTask?.cancel()
        query = text
        Task { await run(text) }
    }

    private func run(_ text: String) async {
        isSearching = true
        defer { isSearching = false }
        do { shelves = try await APIClient.shared.search(text) }
        catch { shelves = [] }
    }
}
