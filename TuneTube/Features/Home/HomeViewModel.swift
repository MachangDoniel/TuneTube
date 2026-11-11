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

    func load(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            shelves = try await APIClient.shared.home(forceRefresh: forceRefresh)
            hasLoaded = true
        } catch {
            if shelves.isEmpty {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
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
