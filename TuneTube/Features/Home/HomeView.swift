import SwiftUI

struct HomeView: View {
    @State private var model = HomeViewModel()
    @Environment(Navigator.self) private var navigator
    @Environment(AuthService.self) private var auth

    private var recentStore = RecentStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text("\(model.greeting), \(auth.greetingName)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                if !recentStore.items.isEmpty {
                    recentlyPlayedSection
                }

                if model.shelves.isEmpty, model.isLoading {
                    ForEach(0..<3, id: \.self) { _ in ShelfSkeleton() }
                } else if let error = model.errorMessage, model.shelves.isEmpty {
                    ErrorState(message: error) { Task { await model.load() } }
                } else {
                    ForEach(model.shelves) { shelf in
                        ShelfRow(shelf: shelf) { item in
                            navigator.open(item, within: shelf.items)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task {
            await model.loadIfNeeded()
        }
        .refreshable {
            recentStore.load()
            await model.load()
        }
    }

    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recently Played")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(recentStore.items) { item in
                        RecentMediaCard(item: item) {
                            navigator.open(item, within: recentStore.items)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct ErrorState: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
    }
}
