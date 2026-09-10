import SwiftUI

/// Sheet allowing users to create or edit a playlist with customizable icons and colors.
///
/// Default icon is Love ("heart.fill"). Also supports Star, Circle, Home, Rectangle,
/// and other common icons, each customizable with a palette of vibrant colors.
struct PlaylistCustomizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var playlistToEdit: LocalPlaylist?
    var onSave: (String, String, String) -> Void

    @State private var name: String = ""
    @State private var selectedIcon: String = "heart.fill"
    @State private var selectedColorHex: String = "#FF2D55"

    struct IconOption: Identifiable {
        let id: String
        let name: String
        let symbol: String
    }

    private let iconOptions: [IconOption] = [
        IconOption(id: "heart.fill", name: "Love", symbol: "heart.fill"),
        IconOption(id: "star.fill", name: "Star", symbol: "star.fill"),
        IconOption(id: "circle.fill", name: "Circle", symbol: "circle.fill"),
        IconOption(id: "house.fill", name: "Home", symbol: "house.fill"),
        IconOption(id: "square.fill", name: "Rectangle", symbol: "square.fill"),
        IconOption(id: "music.note.list", name: "Music", symbol: "music.note.list"),
        IconOption(id: "flame.fill", name: "Flame", symbol: "flame.fill"),
        IconOption(id: "bolt.fill", name: "Bolt", symbol: "bolt.fill"),
        IconOption(id: "bookmark.fill", name: "Bookmark", symbol: "bookmark.fill"),
    ]

    private let colorPalette: [String] = [
        "#FF2D55", // Pink (Love default)
        "#FF3B30", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#30B0C7", // Teal
        "#007AFF", // Blue
        "#AF52DE", // Purple
        "#5856D6", // Indigo
    ]

    init(playlist: LocalPlaylist? = nil, defaultColorHex: String? = nil, onSave: @escaping (String, String, String) -> Void) {
        self.playlistToEdit = playlist
        self.onSave = onSave
        _name = State(initialValue: playlist?.name ?? "")
        _selectedIcon = State(initialValue: playlist?.iconName ?? "heart.fill")
        _selectedColorHex = State(initialValue: playlist?.colorHex ?? defaultColorHex ?? "#FF2D55")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Live Preview Card
                    VStack(spacing: 12) {
                        Image(systemName: selectedIcon)
                            .font(.system(size: 40))
                            .foregroundStyle(Color(hex: selectedColorHex))
                            .frame(width: 88, height: 88)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color(hex: selectedColorHex).opacity(0.4), lineWidth: 2)
                            )
                            .shadow(color: Color(hex: selectedColorHex).opacity(0.25), radius: 10, y: 4)

                        Text(name.isEmpty ? "Playlist Name" : name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(name.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    }
                    .padding(.top, 16)

                    // Name Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)

                        TextField("Enter playlist name", text: $name)
                            .padding(14)
                            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.horizontal, 20)

                    // Icon Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose Icon")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                            ForEach(iconOptions) { option in
                                Button {
                                    selectedIcon = option.symbol
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 20))
                                            .foregroundStyle(selectedIcon == option.symbol ? Color(hex: selectedColorHex) : Theme.textSecondary)
                                            .frame(width: 48, height: 48)
                                            .background(
                                                selectedIcon == option.symbol
                                                    ? Color(hex: selectedColorHex).opacity(0.18)
                                                    : Theme.surfaceHigh,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(
                                                        selectedIcon == option.symbol
                                                            ? Color(hex: selectedColorHex)
                                                            : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )

                                        Text(option.name)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Color Picker
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose Color")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)

                        HStack(spacing: 12) {
                            ForEach(colorPalette, id: \.self) { hex in
                                Button {
                                    selectedColorHex = hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColorHex == hex ? 3 : 0)
                                        )
                                        .shadow(color: Color(hex: hex).opacity(0.4), radius: 4, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(playlistToEdit == nil ? "New Playlist" : "Edit Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(playlistToEdit == nil ? "Create" : "Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, selectedIcon, selectedColorHex)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
