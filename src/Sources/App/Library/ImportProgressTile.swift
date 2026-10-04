import SwiftUI
import WallpaperCore

struct ImportProgressTile: View {
    let entry: PendingImport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(.quaternary)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        ProgressView(value: entry.progress)
                            .padding(.horizontal, 24)
                        Text("Importing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(entry.fileName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
