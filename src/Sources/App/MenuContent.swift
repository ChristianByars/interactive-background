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

        if model.launchAtLogin.status == .requiresApproval {
            Button("Approve Launch at Login…") { model.launchAtLogin.openLoginItemsSettings() }
        } else {
            Toggle("Launch at Login", isOn: Binding(
                get: { model.launchAtLogin.isEnabled },
                set: { model.launchAtLogin.setEnabled($0) }
            ))
        }

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func picker(for display: DisplayInfo) -> some View {
        Picker(display.name, selection: Binding(
            get: { model.store.resolve(display: display.id, main: model.mainDisplayID) },
            set: { model.assign(itemID: $0, to: display.id) }
        )) {
            // Missing items can't be assigned, so they aren't offered; the selection
            // never names one (resolve falls back to Aurora).
            ForEach(model.store.items.filter { !model.store.missingIDs.contains($0.id) }) { item in
                Text(item.name).tag(item.id)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
