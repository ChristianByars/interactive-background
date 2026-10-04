import AppKit
import Observation
import WallpaperCore
import WallpaperEngine

@MainActor
@Observable
final class AppModel {
    let store: LibraryStore
    let engine = WallpaperEngine()
    let importQueue: ImportQueue

    private(set) var displays: [DisplayInfo] = []
    var selectedDisplay: DisplayID?
    var manualPause = false {
        didSet { engine.setManualPause(manualPause) }
    }

    var errorMessages: [String] { importQueue.errors }
    var mainDisplayID: DisplayID? { displays.first(where: \.isMain)?.id }

    init() {
        // Testing hook: IB_LIBRARY_ROOT redirects the library so smoke runs never touch the real one.
        let override = ProcessInfo.processInfo.environment["IB_LIBRARY_ROOT"]
        let root = (override?.isEmpty == false)
            ? URL(fileURLWithPath: override!, isDirectory: true)
            : LibraryStore.defaultRoot
        let store = LibraryStore(root: root)
        self.store = store
        self.importQueue = ImportQueue(
            root: root,
            existingNames: { Set(store.items.map(\.name)) },
            onImported: { store.add($0) })
    }

    func start() {
        store.load()

        engine.onDisplaysChanged = { [weak self] infos in
            guard let self else { return }
            displays = infos
            if selectedDisplay == nil || !infos.contains(where: { $0.id == self.selectedDisplay }) {
                selectedDisplay = infos.first(where: \.isMain)?.id ?? infos.first?.id
            }
        }
        engine.onPlaybackFailed = { [weak self] itemID in self?.playbackFailed(itemID) }
        engine.start { [weak self] display in
            self?.spec(for: display) ?? Self.auroraSpec
        }
    }

    // MARK: Actions

    func assign(itemID: String, to display: DisplayID) {
        store.assign(display: display, itemID: itemID)
        engine.refresh()
    }

    func assignToAll(itemID: String) {
        store.assignAll(displays: displays.map(\.id), itemID: itemID)
        engine.refresh()
    }

    /// The store reassigns affected displays to Aurora and deletes the folder;
    /// the engine then rebuilds those displays (unlinking an open file is safe).
    func remove(itemID: String) {
        store.remove(id: itemID)
        engine.refresh()
    }

    func rename(itemID: String, to name: String) {
        store.rename(id: itemID, to: name)
    }

    func updateSettings(itemID: String, _ settings: VideoSettings) {
        store.updateSettings(id: itemID, settings)
        engine.applySettings(itemID: itemID, settings)
    }

    func `import`(urls: [URL]) {
        importQueue.enqueue(urls)
    }

    func dismissErrors() { importQueue.dismissErrors() }

    // MARK: Private

    private static let auroraSpec = RenderSpec.web(
        itemID: WallpaperItem.auroraID,
        indexURL: BuiltinResources.indexURL(folder: "aurora"))

    private func spec(for display: DisplayID) -> RenderSpec {
        let itemID = store.resolve(display: display, main: NSScreen.mainDisplayStableID())
        guard let item = store.items.first(where: { $0.id == itemID }) else { return Self.auroraSpec }
        switch item.source {
        case .web(let folder):
            return .web(itemID: item.id, indexURL: BuiltinResources.indexURL(folder: folder))
        case .video:
            guard let url = store.videoURL(for: item) else { return Self.auroraSpec }
            return .video(itemID: item.id, fileURL: url, settings: item.settings ?? VideoSettings())
        }
    }

    private func playbackFailed(_ itemID: String) {
        // Aurora is the fallback itself; there is nothing safer to switch to.
        guard itemID != WallpaperItem.auroraID else { return }
        let main = NSScreen.mainDisplayStableID()
        let affected = displays.map(\.id).filter { store.resolve(display: $0, main: main) == itemID }
        store.markMissing(id: itemID)
        for display in affected { store.assign(display: display, itemID: WallpaperItem.auroraID) }
        engine.refresh()
    }
}
