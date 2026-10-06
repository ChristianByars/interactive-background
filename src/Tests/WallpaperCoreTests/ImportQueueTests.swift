import Foundation
import Testing
@testable import WallpaperCore

@MainActor
@Suite("ImportQueue")
struct ImportQueueTests {
    private func makeQueue(
        root: URL, environment: ImportEnvironment = .live,
        existing: Set<String> = [],
        onImported: @escaping (WallpaperItem) -> Void
    ) -> ImportQueue {
        ImportQueue(root: root, existingNames: { existing },
                    environment: environment, onImported: onImported)
    }

    @Test func importsInOrderAndReportsEach() async throws {
        let dir = TempDir(), root = TempDir()
        var urls: [URL] = []
        for name in ["a", "b", "c"] {
            let u = dir.file("\(name).mov")
            try await TestVideo.make(at: u, frames: 5)
            urls.append(u)
        }
        var imported: [String] = []
        let queue = makeQueue(root: root.url) { imported.append($0.name) }
        queue.enqueue(urls)
        #expect(queue.pending.map(\.fileName) == ["a.mov", "b.mov", "c.mov"])
        await queue.waitUntilIdle()
        #expect(imported == ["a", "b", "c"])
        #expect(queue.pending.isEmpty)
        #expect(queue.errors.isEmpty)
    }

    @Test func neverRunsTwoImportsAtOnce() async throws {
        let dir = TempDir(), root = TempDir()
        var urls: [URL] = []
        for name in ["a", "b", "c"] {
            let u = dir.file("\(name).mov")
            try await TestVideo.make(at: u, frames: 5)
            urls.append(u)
        }
        let active = LockedBox(0), maxActive = LockedBox(0), order = LockedBox<[String]>([])
        let environment = ImportEnvironment(
            availableCapacity: { _ in Int64.max },
            copy: { src, dst in
                active.mutate { $0 += 1 }
                maxActive.mutate { $0 = max($0, active.value) }
                order.mutate { $0.append(src.lastPathComponent) }
                Thread.sleep(forTimeInterval: 0.1)
                try FileManager.default.copyItem(at: src, to: dst)
                active.mutate { $0 -= 1 }
            },
            makeThumbnail: { _, _ in })
        let queue = makeQueue(root: root.url, environment: environment) { _ in }
        queue.enqueue(urls)
        await queue.waitUntilIdle()
        #expect(maxActive.value == 1)
        #expect(order.value == ["a.mov", "b.mov", "c.mov"])
    }

    @Test func collectsErrorsWithoutStoppingTheRest() async throws {
        let dir = TempDir(), root = TempDir()
        let good1 = dir.file("good1.mov"), good2 = dir.file("good2.mov")
        try await TestVideo.make(at: good1, frames: 5)
        try await TestVideo.make(at: good2, frames: 5)
        let notes = try TestVideo.makeNotes(at: dir.file("notes.txt"))
        let bad = try TestVideo.makeBadMov(at: dir.file("bad.mov"))

        var imported: [String] = []
        let queue = makeQueue(root: root.url) { imported.append($0.name) }
        queue.enqueue([good1, notes, bad, good2])
        await queue.waitUntilIdle()

        #expect(imported == ["good1", "good2"])
        #expect(queue.errors == [
            "notes.txt isn't a format macOS can play. Use MP4, MOV or M4V.",
            "bad.mov can't be played (unsupported codec or copy-protected).",
        ])
        #expect(queue.pending.isEmpty)

        queue.dismissErrors()
        #expect(queue.errors.isEmpty)
    }

    @Test func insufficientSpaceMessageNamesTheFile() async throws {
        let dir = TempDir(), root = TempDir()
        let u = dir.file("big.mov")
        try await TestVideo.make(at: u, frames: 5)
        let environment = ImportEnvironment(
            availableCapacity: { _ in 0 }, copy: { _, _ in }, makeThumbnail: { _, _ in })
        let queue = makeQueue(root: root.url, environment: environment) { _ in }
        queue.enqueue([u])
        await queue.waitUntilIdle()
        #expect(queue.errors.count == 1)
        #expect(queue.errors[0].hasPrefix("Not enough space to copy big.mov (needs "))
    }

    @Test func duplicateNamesWithinABatchGetSuffixes() async throws {
        let dir = TempDir(), root = TempDir()
        let sub = dir.file("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let a = dir.file("clip.mov"), b = sub.appendingPathComponent("clip.mov")
        try await TestVideo.make(at: a, frames: 5)
        try await TestVideo.make(at: b, frames: 5)
        var names: [String] = []
        let queue = makeQueue(root: root.url, existing: ["clip"]) { names.append($0.name) }
        queue.enqueue([a, b])
        await queue.waitUntilIdle()
        #expect(names == ["clip 2", "clip 3"])
    }

    @Test func enqueueWhileRunningIsAppended() async throws {
        let dir = TempDir(), root = TempDir()
        let a = dir.file("a.mov"), b = dir.file("b.mov")
        try await TestVideo.make(at: a, frames: 5)
        try await TestVideo.make(at: b, frames: 5)
        var names: [String] = []
        let queue = makeQueue(root: root.url) { names.append($0.name) }
        queue.enqueue([a])
        queue.enqueue([b])
        await queue.waitUntilIdle()
        #expect(names == ["a", "b"])
    }
}
