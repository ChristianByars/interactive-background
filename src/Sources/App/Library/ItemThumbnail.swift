import SwiftUI
import WallpaperCore

/// 16:10 preview: thumb.jpg when present, else a gradient (built-ins) or a film symbol (videos).
struct ItemThumbnail: View {
    let item: WallpaperItem
    let store: LibraryStore

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var content: some View {
        if let url = store.thumbnailURL(for: item) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.clear
            }
        } else if item.isBuiltin {
            // Aurora has no thumbnail file; a gradient stands in for it.
            LinearGradient(
                colors: [.teal, .indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Image(systemName: "film")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}
