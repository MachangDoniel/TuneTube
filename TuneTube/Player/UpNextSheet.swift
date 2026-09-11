import SwiftUI

/// The queue: "Playing from", autoplay toggle, and the track list. Long-press a
/// row to drag it, swipe to remove it, tap to jump to it.
struct UpNextSheet: View {
    @Environment(PlayerEngine.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var player = player

        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.queueTitle == nil ? "Up next" : "Playing from")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Text(player.queueTitle ?? "Your queue")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Close queue")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Toggle(isOn: $player.isAutoplayEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Autoplay")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Keep playing similar songs when your queue ends")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                List {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { position, item in
                        Button { player.playFromQueue(at: position) } label: {
                            QueueRow(item: item, isCurrent: position == player.index,
                                     isPlaying: player.isPlaying, isPast: position < player.index)
                                .contentShape(Rectangle())
                        }
                            .buttonStyle(.plain)
                            .id(position)
                            .listRowBackground(position == player.index ? Color.white.opacity(0.08) : Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .deleteDisabled(position == player.index)
                    }
                    .onMove { player.moveInQueue(from: $0, to: $1) }
                    .onDelete { player.removeFromQueue(at: $0) }

                    if player.isExtendingQueue {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Adding similar songs…")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { proxy.scrollTo(player.index, anchor: .top) }
            }
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct QueueRow: View {
    let item: MediaItem
    let isCurrent: Bool
    let isPlaying: Bool
    let isPast: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Artwork(url: item.effectiveThumbnailUrl, size: 48, corner: 6)
                if isCurrent {
                    Color.black.opacity(0.45)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 15, weight: isCurrent ? .bold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .opacity(isPast ? 0.5 : 1)
    }

    private var subtitle: String {
        let parts = [item.displaySubtitle(), item.durationSeconds.map { PlayerView.time(Double($0)) }]
        return parts.compactMap { $0 }.joined(separator: " • ")
    }
}
