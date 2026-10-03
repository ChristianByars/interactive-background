import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
public final class LibraryStore {
    public enum LoadOutcome: Sendable { case fresh, loaded, recovered }

    public nonisolated static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Interactive Background", isDirectory: true)
    }

    public private(set) var items: [WallpaperItem]
    public private(set) var assignments: [DisplayID: String] = [:]
    public private(set) var missingIDs: Set<String> = []

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private let builtins: [WallpaperItem]
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var dirty = false

    public init(
        root: URL = LibraryStore.defaultRoot,
        saveDelay: Duration = .milliseconds(500),
        builtins: [WallpaperItem] = [.aurora]
    ) {
        self.root = root
        self.saveDelay = saveDelay
        self.builtins = builtins
        self.items = builtins
    }

    // MARK: Paths

    public var videosRoot: URL { root.appendingPathComponent("Videos", isDirectory: true) }
    private var libraryURL: URL { root.appendingPathComponent("library.json") }
    private var badURL: URL { root.appendingPathComponent("library.json.bad") }

    public func videoURL(for item: WallpaperItem) -> URL? {
        guard case .video(let path) = item.source else { return nil }
        return root.appendingPathComponent(path)
    }

    public func thumbnailURL(for item: WallpaperItem) -> URL? {
        guard case .video = item.source else { return nil }
        let url = videosRoot.appendingPathComponent(item.id, isDirectory: true)
            .appendingPathComponent("thumb.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Load

    @discardableResult
    public func load() -> LoadOutcome {
        pendingSave?.cancel()
        pendingSave = nil
        dirty = false
        removePartials()

        let outcome: LoadOutcome
        if let data = try? Data(contentsOf: libraryURL) {
            if let file = try? JSONDecoder().decode(LibraryFile.self, from: data) {
                apply(file)
                outcome = .loaded
            } else {
                quarantineCorruptFile()
                apply(LibraryFile())
                readoptOrphans()
                save()
                outcome = .recovered
            }
        } else {
            apply(LibraryFile())
            outcome = .fresh
        }
        refreshMissing()
        return outcome
    }

    private func apply(_ file: LibraryFile) {
        let builtinIDs = Set(builtins.map(\.id))
        items = builtins + file.items.filter { !builtinIDs.contains($0.id) && !$0.isBuiltin }
        assignments = file.assignments
    }

    private func refreshMissing() {
        missingIDs = Set(items.compactMap { item in
            guard let url = videoURL(for: item) else { return nil }
            return FileManager.default.fileExists(atPath: url.path) ? nil : item.id
        })
    }

    private func removePartials() {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: videosRoot, includingPropertiesForKeys: nil) else { return }
        let partials = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "partial" }
        for url in partials { try? fm.removeItem(at: url) }
    }

    private func quarantineCorruptFile() {
        let fm = FileManager.default
        try? fm.removeItem(at: badURL)
        try? fm.moveItem(at: libraryURL, to: badURL)
    }

    /// Re-creates items for `Videos/<uuid>/` folders left behind by a lost library file.
    private func readoptOrphans() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(
            at: videosRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard let video = files.first(where: Self.isVideoFile) else { continue }
            let id = folder.lastPathComponent
            guard !items.contains(where: { $0.id == id }) else { continue }
            let name = uniqueName(video.deletingPathExtension().lastPathComponent)
            items.append(WallpaperItem(
                id: id, name: name,
                source: .video(path: "Videos/\(id)/\(video.lastPathComponent)"),
                settings: VideoSettings()))
        }
    }

    private static func isVideoFile(_ url: URL) -> Bool {
        guard !url.lastPathComponent.hasPrefix("."),
              let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .movie)
    }

    // MARK: Mutations

    public func add(_ item: WallpaperItem) {
        guard !item.isBuiltin, !items.contains(where: { $0.id == item.id }) else { return }
        var item = item
        item.name = uniqueName(item.name)
        items.append(item)
        saveNow()
    }

    public func rename(id: String, to name: String) {
        guard let i = storedIndex(of: id) else { return }
        items[i].name = name
        scheduleSave()
    }

    public func updateSettings(id: String, _ settings: VideoSettings) {
        guard let i = storedIndex(of: id) else { return }
        items[i].settings = settings
        scheduleSave()
    }

    public func assign(display: DisplayID, itemID: String) {
        assignments[display] = itemID
        saveNow()
    }

    public func assignAll(displays: [DisplayID], itemID: String) {
        for display in displays { assignments[display] = itemID }
        saveNow()
    }

    public func remove(id: String) {
        guard let i = storedIndex(of: id) else { return }
        items.remove(at: i)
        for (display, assigned) in assignments where assigned == id {
            assignments[display] = WallpaperItem.auroraID
        }
        missingIDs.remove(id)
        try? FileManager.default.removeItem(
            at: videosRoot.appendingPathComponent(id, isDirectory: true))
        saveNow()
    }

    public func markMissing(id: String) {
        guard items.contains(where: { $0.id == id }) else { return }
        missingIDs.insert(id)
    }

    public func resolve(display: DisplayID, main: DisplayID?) -> String {
        DisplayAssignments.resolve(
            display: display, main: main, assignments: assignments,
            missing: missingIDs, knownItemIDs: Set(items.map(\.id)))
    }

    /// Writes any debounced change to disk immediately.
    public func flush() {
        guard dirty else { return }
        saveNow()
    }

    // MARK: Helpers

    /// Index of a stored (non-builtin) item.
    private func storedIndex(of id: String) -> Int? {
        items.firstIndex { $0.id == id && !$0.isBuiltin }
    }

    private func uniqueName(_ base: String) -> String {
        let taken = Set(items.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Persistence

    private func scheduleSave() {
        dirty = true
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    private func save() {
        let file = LibraryFile(items: items.filter { !$0.isBuiltin }, assignments: assignments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try encoder.encode(file).write(to: libraryURL, options: .atomic)
            dirty = false
        } catch {
            dirty = true
        }
    }
}
