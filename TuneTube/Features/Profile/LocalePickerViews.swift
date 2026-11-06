import SwiftUI

/// Picks the content region (`gl`). Changing it clears the response cache and
/// every feed reloads behind this screen.
struct RegionPickerView: View {
    @Environment(AppSettings.self) private var settings
    @State private var filter = ""

    private var matches: [ContentRegion] {
        let text = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ContentRegion.all }
        return ContentRegion.all.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.code.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        LocalePickerList(
            filter: $filter,
            filterPrompt: "Search countries",
            footer: "Changes your home feed, charts and search results to what's popular in the selected country."
        ) {
            ForEach(matches) { region in
                LocaleRow(
                    leading: Text(region.flag).font(.system(size: 26)),
                    title: region.name,
                    subtitle: region.code,
                    isSelected: region.code == settings.region
                ) {
                    settings.setRegion(region.code)
                }
            }
        }
        .navigationTitle("Region")
    }
}

/// Picks the content language (`hl`).
struct LanguagePickerView: View {
    @Environment(AppSettings.self) private var settings
    @State private var filter = ""

    private var matches: [ContentLanguage] {
        let text = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ContentLanguage.all }
        return ContentLanguage.all.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.nativeName.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        LocalePickerList(
            filter: $filter,
            filterPrompt: "Search languages",
            footer: "Sets the language titles and descriptions come back in. It does not translate the app itself."
        ) {
            ForEach(matches) { language in
                LocaleRow(
                    leading: Image(systemName: "character.bubble")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30),
                    title: language.name,
                    subtitle: language.nativeName,
                    isSelected: language.code == settings.language
                ) {
                    settings.setLanguage(language.code)
                }
            }
        }
        .navigationTitle("Language")
    }
}

// MARK: - Shared chrome

private struct LocalePickerList<Rows: View>: View {
    @Binding var filter: String
    let filterPrompt: String
    let footer: String
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textSecondary)
                TextField(filterPrompt, text: $filter)
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !filter.isEmpty {
                    Button { filter = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            List {
                rows
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.top, 8)
        .navigationBarTitleDisplayMode(.inline)
        .screenBackground()
    }
}

private struct LocaleRow<Leading: View>: View {
    let leading: Leading
    let title: String
    let subtitle: String
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.white.opacity(0.06))
    }
}
