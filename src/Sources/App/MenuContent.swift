import AppKit
import SwiftUI
import WallpaperCore
import WallpaperEngine

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.displays.count == 1, let only = model.displays.first {
            picker(for: only)
        } else {
            ForEach(model.displays, id: \.id) { display in
                Menu(display.name) { picker(for: display) }
            }
        }

        Divider()

        Toggle("Pause All", isOn: $model.manualPause)
            .keyboardShortcut("p", modifiers: .option)

        Button("Open Library…") {
            openWindow(id: "library")
            NSApp.activate()
        }
        .keyboardShortcut("l")

        Divider()

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func picker(for display: DisplayInfo) -> some View {
        Picker(display.name, selection: Binding(
            get: { model.store.resolve(display: display.id, main: model.mainDisplayID) },
            set: { model.assign(itemID: $0, to: display.id) }
        )) {
            ForEach(model.store.items) { item in
                Text(model.store.missingIDs.contains(item.id) ? "\(item.name) (missing)" : item.name)
                    .tag(item.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
