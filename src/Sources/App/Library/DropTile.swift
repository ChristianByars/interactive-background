import SwiftUI

/// Dashed target; dropping files is handled by the window, clicking opens the file picker.
struct DropTile: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title2)
                        Text("Drop videos here")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
