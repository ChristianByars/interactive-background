import Foundation
import Testing
@testable import WallpaperCore

@MainActor
final class Sandbox {
    let root: URL
    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    var libraryJSON: URL { root.appendingPathComponent("library.json") }
    var badJSON: URL { root.appendingPathComponent("library.json.bad") }
    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    func makeStore(saveDelay: Duration = .milliseconds(30)) -> LibraryStore {
        LibraryStore(root: root, saveDelay: saveDelay)
    }

    /// Creates `Videos/<id>/<file>` on disk and returns a matching library item.
    @discardableResult
    func makeVideo(id: String = UUID().uuidString, name: String = "clip",
                   file: String = "clip.mp4") throws -> WallpaperItem {
        let dir = root.appendingPathComponent("Videos/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: dir.appendingPathComponent(file))
        return WallpaperItem(id: id, name: name, source: .video(path: "Videos/\(id)/\(file)"),
                             settings: VideoSettings())
    }

    func rawJSON() throws -> String {
        String(decoding: try Data(contentsOf: libraryJSON), as: UTF8.self)
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
@Suite struct LibraryStoreTests {
    @Test func freshRootHasOnlyBuiltins() {
        let sb = Sandbox()
        let store = sb.makeStore()
        #expect(store.load() == .fresh)
        #expect(store.items == [WallpaperItem.aurora])
        #expect(store.assignments.isEmpty)
        #expect(store.missingIDs.isEmpty)
    }

    @Test func defaultRootIsApplicationSupport() {
        #expect(LibraryStore.defaultRoot.path.hasSuffix(
            "Library/Application Support/Interactive Background"))
    }

    @Test func persistsAndReloadsViaSecondInstance() throws {
        let sb = Sandbox()
        let a = sb.makeStore()
        a.load()
        let item = try sb.makeVideo(name: "Waves")
        a.add(item)

        let b = sb.makeStore()
        #expect(b.load() == .loaded)
        #expect(b.items.map(\.id) == [WallpaperItem.auroraID, item.id])
        #expect(b.items.last == item)
    }

    @Test func rawJSONHasVersionAndNoBuiltin() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        store.add(try sb.makeVideo(name: "Waves"))
        let json = try sb.rawJSON()
        #expect(json.contains("\"version\" : 1"))
        #expect(!json.contains("builtin.aurora"))
        #expect(json.contains("Waves"))
    }

    @Test func assignmentsSurviveReload() throws {
        let sb = Sandbox()
        let a = sb.makeStore()
        a.load()
        let item = try sb.makeVideo()
        a.add(item)
        a.assign(display: "D1", itemID: item.id)
        a.assignAll(displays: ["D2", "D3"], itemID: WallpaperItem.auroraID)

        let b = sb.makeStore()
        b.load()
        #expect(b.assignments == ["D1": item.id, "D2": WallpaperItem.auroraID,
                                  "D3": WallpaperItem.auroraID])
    }

    @Test func settingsAndRenameAreDebouncedUntilFlush() async throws {
        let sb = Sandbox()
        // Long delay so only flush() can write within the test.
        let store = sb.makeStore(saveDelay: .seconds(60))
        store.load()
        let item = try sb.makeVideo(name: "Old")
        store.add(item)

        store.rename(id: item.id, to: "New")
        store.updateSettings(id: item.id, VideoSettings(fit: .fit, speed: 1.5))
        #expect(try sb.rawJSON().contains("Old"))
        #expect(!(try sb.rawJSON().contains("New")))

        store.flush()
        let json = try sb.rawJSON()
        #expect(json.contains("New"))
        #expect(json.contains("\"fit\" : \"fit\""))

        let b = sb.makeStore()
        b.load()
        #expect(b.items.last?.name == "New")
        #expect(b.items.last?.settings?.speed == 1.5)
    }

    @Test func debouncedSaveFiresAfterDelay() async throws {
        let sb = Sandbox()
        let store = sb.makeStore(saveDelay: .milliseconds(30))
        store.load()
        let item = try sb.makeVideo(name: "Old")
        store.add(item)
        store.rename(id: item.id, to: "Renamed")
        let saved = await waitUntil { (try? sb.rawJSON().contains("Renamed")) == true }
        #expect(saved)
    }

    @Test func corruptJSONIsQuarantinedAndVideosReadopted() async throws {
        let sb = Sandbox()
        let orphan = try sb.makeVideo(id: "11111111-2222-3333-4444-555555555555",
                                      name: "Sunset", file: "Sunset.mov")
        try Data("not json {{{".utf8).write(to: sb.libraryJSON)
        // A stale .bad from an earlier crash must be replaced.
        try Data("old bad".utf8).write(to: sb.badJSON)

        let store = sb.makeStore()
        #expect(store.load() == .recovered)

        #expect(sb.exists("library.json.bad"))
        #expect(String(decoding: try Data(contentsOf: sb.badJSON), as: UTF8.self)
                == "not json {{{")
        #expect(sb.exists("Videos/\(orphan.id)/Sunset.mov"))
        #expect(store.items.map(\.id) == [WallpaperItem.auroraID, orphan.id])
        let adopted = try #require(store.items.last)
        #expect(adopted.name == "Sunset")
        #expect(adopted.source == .video(path: "Videos/\(orphan.id)/Sunset.mov"))
        #expect(adopted.settings == VideoSettings())

        // Recovered state was written back, so a new instance loads cleanly.
        let again = sb.makeStore()
        #expect(again.load() == .loaded)
        #expect(again.items.map(\.id) == store.items.map(\.id))
    }

    @Test func deletedVideoFileIsMissingAndResolvesToAurora() throws {
        let sb = Sandbox()
        let a = sb.makeStore()
        a.load()
        let item = try sb.makeVideo()
        a.add(item)
        a.assign(display: "D1", itemID: item.id)
        #expect(a.resolve(display: "D1", main: "D1") == item.id)

        try FileManager.default.removeItem(
            at: sb.root.appendingPathComponent("Videos/\(item.id)/clip.mp4"))

        let b = sb.makeStore()
        b.load()
        #expect(b.missingIDs == [item.id])
        #expect(b.resolve(display: "D1", main: "D1") == WallpaperItem.auroraID)
    }

    @Test func markMissingFallsBackToAurora() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        let item = try sb.makeVideo()
        store.add(item)
        store.assign(display: "D1", itemID: item.id)
        store.markMissing(id: item.id)
        #expect(store.missingIDs == [item.id])
        #expect(store.resolve(display: "D1", main: "D1") == WallpaperItem.auroraID)
    }

    @Test func removeDeletesFolderAndAssignsAurora() throws {
        let sb = Sandbox()
        let store = sb.makeStore(saveDelay: .seconds(60))
        store.load()
        let item = try sb.makeVideo()
        let other = try sb.makeVideo(name: "Other")
        store.add(item)
        store.add(other)
        store.assign(display: "D1", itemID: item.id)
        store.assign(display: "D2", itemID: item.id)
        store.assign(display: "D3", itemID: other.id)
        store.markMissing(id: item.id)

        store.remove(id: item.id)

        #expect(!sb.exists("Videos/\(item.id)"))
        #expect(sb.exists("Videos/\(other.id)"))
        #expect(store.items.map(\.id) == [WallpaperItem.auroraID, other.id])
        #expect(store.assignments == ["D1": WallpaperItem.auroraID,
                                      "D2": WallpaperItem.auroraID,
                                      "D3": other.id])
        #expect(!store.missingIDs.contains(item.id))

        // Saved immediately (no flush).
        let b = sb.makeStore()
        b.load()
        #expect(b.items.map(\.id) == [WallpaperItem.auroraID, other.id])
        #expect(b.assignments["D1"] == WallpaperItem.auroraID)
    }

    @Test func removingBuiltinIsNoOp() {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        store.assign(display: "D1", itemID: WallpaperItem.auroraID)
        store.remove(id: WallpaperItem.auroraID)
        #expect(store.items == [WallpaperItem.aurora])
        #expect(store.assignments == ["D1": WallpaperItem.auroraID])
    }

    @Test func duplicateNamesGetNumericSuffix() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        for _ in 0..<3 { store.add(try sb.makeVideo(name: "Waves")) }
        #expect(store.items.dropFirst().map(\.name) == ["Waves", "Waves 2", "Waves 3"])
    }

    @Test func addingSameIDTwiceIsIgnored() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        let item = try sb.makeVideo(name: "Waves")
        store.add(item)
        store.add(item)
        #expect(store.items.count == 2)
    }

    @Test func partialFilesAreDeletedOnLoad() throws {
        let sb = Sandbox()
        let item = try sb.makeVideo()
        let dir = sb.root.appendingPathComponent("Videos/\(item.id)")
        try Data("x".utf8).write(to: dir.appendingPathComponent("big.mov.partial"))
        let nested = sb.root.appendingPathComponent("Videos/deep/er", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nested.appendingPathComponent("x.mp4.partial"))

        let store = sb.makeStore()
        store.load()
        #expect(!sb.exists("Videos/\(item.id)/big.mov.partial"))
        #expect(!sb.exists("Videos/deep/er/x.mp4.partial"))
        #expect(sb.exists("Videos/\(item.id)/clip.mp4"))
    }

    @Test func unknownDisplayResolvesToMainsChoice() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        let item = try sb.makeVideo()
        store.add(item)
        store.assign(display: "MAIN", itemID: item.id)
        #expect(store.resolve(display: "NEW", main: "MAIN") == item.id)
        #expect(store.resolve(display: "NEW", main: nil) == WallpaperItem.auroraID)
    }

    @Test func urlsAreRootRelative() throws {
        let sb = Sandbox()
        let store = sb.makeStore()
        store.load()
        let item = try sb.makeVideo(name: "Waves")
        store.add(item)
        #expect(store.videoURL(for: item)
                == sb.root.appendingPathComponent("Videos/\(item.id)/clip.mp4"))
        #expect(store.videoURL(for: .aurora) == nil)
        #expect(store.videosRoot == sb.root.appendingPathComponent("Videos"))

        #expect(store.thumbnailURL(for: item) == nil)
        let thumb = sb.root.appendingPathComponent("Videos/\(item.id)/thumb.jpg")
        try Data("jpg".utf8).write(to: thumb)
        #expect(store.thumbnailURL(for: item) == thumb)
        #expect(store.thumbnailURL(for: .aurora) == nil)
    }
}
