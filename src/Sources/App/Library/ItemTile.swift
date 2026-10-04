import AVFoundation
import SwiftUI
import WallpaperCore

struct ItemTile: View {
    let item: WallpaperItem
    let store: LibraryStore
    let isCurrent: Bool
    let onSelect: () -> Void

    @State private var duration: Double?

    private var isMissing: Bool { store.missingIDs.contains(item.id) }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                ItemThumbnail(item: item, store: store)
                    .overlay(alignment: .bottomTrailing) { badge }
                    .overlay(alignment: .topTrailing) { checkmark }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.accentColor, lineWidth: isCurrent ? 2 : 0)
                    }
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: item.id) { await loadDuration() }
    }

    private var badge: some View {
        Text(badgeText)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isMissing ? Color.red : Color.black.opacity(0.6), in: Capsule())
            .padding(6)
    }

    @ViewBuilder private var checkmark: some View {
        if isCurrent {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, Color.accentColor)
                .padding(6)
                .accessibilityLabel("Current wallpaper")
        }
    }

    private var badgeText: String {
        if isMissing { return "File missing" }
        if item.isBuiltin { return "Built-in" }
        guard let duration else { return "Video" }
        return Self.format(duration)
    }

    // The model stores no duration, so read it from the file; "Video" shows until then.
    private func loadDuration() async {
        guard !isMissing, let url = store.videoURL(for: item) else { return }
        guard let time = try? await AVURLAsset(url: url).load(.duration) else { return }
        let seconds = time.seconds
        if seconds.isFinite, seconds > 0 { duration = seconds }
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
