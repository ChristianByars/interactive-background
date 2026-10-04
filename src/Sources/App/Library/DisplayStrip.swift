import SwiftUI
import WallpaperCore
import WallpaperEngine

/// One card per display; the selected one is the target for tile clicks.
struct DisplayStrip: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.displays, id: \.id) { display in
                    card(for: display)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func card(for display: DisplayInfo) -> some View {
        let selected = display.id == model.selectedDisplay
        let itemID = model.store.resolve(display: display.id, main: model.mainDisplayID)
        let item = model.store.items.first { $0.id == itemID } ?? .aurora
        return Button { model.selectedDisplay = display.id } label: {
            HStack(spacing: 8) {
                ItemThumbnail(item: item, store: model.store)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name).font(.callout).lineLimit(1)
                    Text(item.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: selected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
