import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var showImporter = false
    @State private var showInspector = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.errorMessages.isEmpty {
                ErrorBanner(messages: model.errorMessages, onDismiss: model.dismissErrors)
            }
            DisplayStrip(model: model)
            ItemGrid(model: model, onImportTap: { showImporter = true })
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 400)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Button { showImporter = true } label: {
                    Label("Import", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .fileImporter(
            isPresented: $showImporter, allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.import(urls: urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            model.import(urls: files)
            return true
        }
        // The Dock icon exists only while this window does; the app is otherwise menu-bar-only.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
