import SwiftUI
import WallpaperCore

struct ItemGrid: View {
    @Bindable var model: AppModel
    let onImportTap: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .top)]

    /// The item currently shown on the selected display (✓).
    private var currentID: String? {
        guard let display = model.selectedDisplay else { return nil }
        return model.store.resolve(display: display, main: model.mainDisplayID)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(model.store.items) { item in
                    ItemTile(
                        item: item, store: model.store, isCurrent: item.id == currentID,
                        onSelect: { select(item) },
                        onSetOnAllDisplays: { model.assignToAll(itemID: item.id) },
                        onRename: { model.rename(itemID: item.id, to: $0) },
                        onRemove: { model.remove(itemID: item.id) })
                }
                ForEach(model.importQueue.pending) { entry in
                    ImportProgressTile(entry: entry)
                }
                DropTile(onTap: onImportTap)
            }
            .padding(.vertical, 4)
        }
    }

    private func select(_ item: WallpaperItem) {
        guard let display = model.selectedDisplay else { return }
        model.assign(itemID: item.id, to: display)
    }
}
