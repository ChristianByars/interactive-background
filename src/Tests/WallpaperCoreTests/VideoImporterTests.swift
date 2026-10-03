import Foundation
import Testing
@testable import WallpaperCore

private struct Boom: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

/// Environment that behaves like `.live` except where overridden.
private func env(
    capacity: @escaping @Sendable (URL) throws -> Int64 = { _ in Int64.max },
    copy: @escaping @Sendable (URL, URL) throws -> Void = ImportEnvironment.live.copy,
    thumbnail: @escaping @Sendable (URL, URL) async throws -> Void = ImportEnvironment.live.makeThumbnail
) -> ImportEnvironment {
    ImportEnvironment(availableCapacity: capacity, copy: copy, makeThumbnail: thumbnail)
}

private func noProgress(_: Double) {}

@Suite("VideoImporter")
struct VideoImporterTests {
    @Test func textFileIsUnsupportedFormat() async throws {
        let dir = TempDir(), root = TempDir()
        let src = try TestVideo.makeNotes(at: dir.file("notes.txt"))
        await #expect(throws: ImportError.unsupportedFormat("notes.txt")) {
            try await importVideo(from: src, root: root.url, existingNames: [],
                                  environment: env(), progress: noProgress)
        }
        #expect(!root.exists("Videos"))
    }

    @Test func randomBytesMovIsNotPlayable() async throws {
        let dir = TempDir(), root = TempDir()
        let src = try TestVideo.makeBadMov(at: dir.file("bad.mov"))
        await #expect(throws: ImportError.notPlayable("bad.mov")) {
            try await importVideo(from: src, root: root.url, existingNames: [],
                                  environment: env(), progress: noProgress)
        }
        #expect(!root.exists("Videos"))
    }

    @Test func zeroCapacityIsInsufficientSpace() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        let size = try #require(
            try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int64)
        await #expect(throws: ImportError.insufficientSpace(needed: size)) {
            try await importVideo(from: src, root: root.url, existingNames: [],
                                  environment: env(capacity: { _ in 0 }), progress: noProgress)
        }
        #expect(!root.exists("Videos"))
    }

    @Test func throwingCopyIsCopyFailedAndLeavesNoFolder() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        await #expect(throws: ImportError.copyFailed("boom")) {
            try await importVideo(from: src, root: root.url, existingNames: [],
                                  environment: env(copy: { _, _ in throw Boom() }),
                                  progress: noProgress)
        }
        let videos = root.url.appendingPathComponent("Videos")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: videos.path)) ?? []
        #expect(left.isEmpty)
    }

    @Test func partialCopyIsCleanedUpOnFailure() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        await #expect(throws: ImportError.self) {
            try await importVideo(
                from: src, root: root.url, existingNames: [],
                environment: env(copy: { _, dst in
                    try Data("half".utf8).write(to: dst)
                    throw Boom()
                }), progress: noProgress)
        }
        let videos = root.url.appendingPathComponent("Videos")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: videos.path)) ?? []).isEmpty)
    }

    @Test func successCopiesFileWritesThumbnailAndBuildsItem() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("My Clip.mov")
        try await TestVideo.make(at: src)

        let item = try await importVideo(from: src, root: root.url, existingNames: [],
                                         progress: noProgress)

        #expect(item.name == "My Clip")
        #expect(item.settings == VideoSettings())
        #expect(!item.isBuiltin)
        #expect(UUID(uuidString: item.id) != nil)
        #expect(item.source == .video(path: "Videos/\(item.id)/My Clip.mov"))
        #expect(root.exists("Videos/\(item.id)/My Clip.mov"))
        #expect(root.exists("Videos/\(item.id)/thumb.jpg"))
        #expect(!root.exists("Videos/\(item.id)/My Clip.mov.partial"))
        #expect(FileManager.default.fileExists(atPath: src.path))  // source untouched

        let thumb = try Data(contentsOf: root.url.appendingPathComponent("Videos/\(item.id)/thumb.jpg"))
        #expect(Array(thumb.prefix(2)) == [0xFF, 0xD8])  // JPEG magic
    }

    @Test func importsIntoRootThatDoesNotExistYet() async throws {
        let dir = TempDir(), parent = TempDir()
        let root = parent.file("Fresh/Library")  // never created
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        #expect(!FileManager.default.fileExists(atPath: root.path))

        let item = try await importVideo(from: src, root: root, existingNames: [],
                                         progress: noProgress)  // live environment
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Videos/\(item.id)/clip.mov").path))
    }

    @Test func capacityIsQueriedOnAnExistingPathAndStillRejects() async throws {
        let dir = TempDir(), parent = TempDir()
        let root = parent.file("Fresh/Library")  // never created
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        let queried = LockedBox<[URL]>([])
        let environment = env(capacity: { url in queried.mutate { $0.append(url) }; return 0 })
        await #expect(throws: ImportError.self) {
            try await importVideo(from: src, root: root, existingNames: [],
                                  environment: environment, progress: noProgress)
        }
        let urls = queried.value
        #expect(urls.count == 1)
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(!FileManager.default.fileExists(atPath: root.path))  // no side effects
    }

    @Test func duplicateNameGetsSuffix() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        let item = try await importVideo(from: src, root: root.url,
                                         existingNames: ["clip"], progress: noProgress)
        #expect(item.name == "clip 2")
    }

    @Test func throwingThumbnailStillImports() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        let item = try await importVideo(
            from: src, root: root.url, existingNames: [],
            environment: env(thumbnail: { _, _ in throw Boom() }), progress: noProgress)
        #expect(root.exists("Videos/\(item.id)/clip.mov"))
        #expect(!root.exists("Videos/\(item.id)/thumb.jpg"))
    }

    @Test func reportsProgressEndingAtOne() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("clip.mov")
        try await TestVideo.make(at: src)
        let box = LockedBox<[Double]>([])
        _ = try await importVideo(from: src, root: root.url, existingNames: [],
                                  progress: { p in box.mutate { $0.append(p) } })
        let values = box.value
        #expect(values.last == 1.0)
        #expect(values.allSatisfy { (0.0...1.0).contains($0) })
    }

    @Test func liveThumbnailFitsWithin480() async throws {
        let dir = TempDir(), root = TempDir()
        let src = dir.file("wide.mov")
        try await TestVideo.make(at: src, frames: 10, size: CGSize(width: 1280, height: 720))
        let item = try await importVideo(from: src, root: root.url, existingNames: [],
                                         progress: noProgress)
        let url = root.url.appendingPathComponent("Videos/\(item.id)/thumb.jpg")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let w = try #require(props[kCGImagePropertyPixelWidth] as? Int)
        let h = try #require(props[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(w, h) <= 480)
        #expect(w > h)
    }

    @Test func errorMessagesMatchSpec() {
        #expect(ImportError.unsupportedFormat("clip.webm").message
                == "clip.webm isn't a format macOS can play. Use MP4, MOV or M4V.")
        #expect(ImportError.notPlayable("a.mov").message
                == "a.mov can't be played (unsupported codec or copy-protected).")
        #expect(ImportError.copyFailed("disk gone").message(forFile: "a.mov")
                == "Copying a.mov failed: disk gone")
        let needed = ByteCountFormatter.string(fromByteCount: 5_000_000, countStyle: .file)
        #expect(ImportError.insufficientSpace(needed: 5_000_000).message(forFile: "a.mov")
                == "Not enough space to copy a.mov (needs \(needed)).")
    }
}

import ImageIO

/// Tiny thread-safe holder for values captured by `@Sendable` closures.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); defer { lock.unlock() }; body(&stored) }
}
