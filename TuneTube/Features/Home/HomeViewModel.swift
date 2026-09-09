import Foundation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var shelves: [Shelf] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let config = try? await APIClient.shared.config()
            let hidden = Set(config?.hiddenShelfIds ?? [])
            let fetched = try await APIClient.shared.home()
            // hiddenShelfIds is the remote kill-switch for a shelf that breaks.
            shelves = fetched.filter { !hidden.contains($0.id) }
            hasLoaded = true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}
