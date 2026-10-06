import AVFoundation
import Foundation
import Testing
import WallpaperCore
@testable import WallpaperEngine

/// Pool behaviour that needs no window: shared players, failure reporting and the
/// stale-load guard. Successful looping is covered by the manual smoke run (see task report).
@MainActor
@Suite struct VideoPoolTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPoolTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func badMov() throws -> URL {
        let url = dir.appendingPathComponent("bad.mov")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        return url
    }

    /// Polls until `condition` holds or `limit` passes.
    private func wait(_ limit: Duration = .seconds(5), until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + limit
        while !condition() && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func gravityFollowsFit() {
        #expect(VideoRenderer.gravity(for: .fill) == .resizeAspectFill)
        #expect(VideoRenderer.gravity(for: .fit) == .resizeAspect)
        #expect(VideoRenderer.gravity(for: .stretch) == .resize)
    }

    @Test func sameItemSharesOnePlayer() throws {
        let pool = VideoPlayerPool()
        let url = try badMov()
        let a = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "A")
        let b = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "B")
        let c = pool.acquire(itemID: "y", fileURL: url, settings: VideoSettings(), displayID: "A")
        #expect(a === b)
        #expect(a !== c)
        #expect(a.preventsDisplaySleepDuringVideoPlayback == false)
        for (item, display) in [("x", "A"), ("x", "B"), ("y", "A")] {
            pool.release(itemID: item, displayID: display)
        }
    }

    @Test func acquireAttachesDisplayWithInitialPauseState() throws {
        let pool = VideoPlayerPool()
        let url = try badMov()
        _ = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "A", paused: true)
        #expect(pool.isPaused(itemID: "x", displayID: "A"))
        // Joining an existing entry takes the passed state, not an implicit "unpaused".
        _ = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "B", paused: true)
        _ = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "C")
        #expect(pool.isPaused(itemID: "x", displayID: "B"))
        #expect(!pool.isPaused(itemID: "x", displayID: "C"))
        for d in ["A", "B", "C"] { pool.release(itemID: "x", displayID: d) }
    }

    @Test func settingsReachSharedPlayer() throws {
        let pool = VideoPlayerPool()
        let player = pool.acquire(itemID: "x", fileURL: try badMov(), settings: VideoSettings(), displayID: "A")
        pool.apply(itemID: "x", settings: VideoSettings(speed: 1.5, audioEnabled: true, volume: 0.25))
        #expect(player.defaultRate == 1.5)
        #expect(player.isMuted == false)
        #expect(player.volume == 0.25)
        pool.release(itemID: "x", displayID: "A")
    }

    @Test func unplayableFileReportsFailureOnce() async throws {
        let pool = VideoPlayerPool()
        var failures: [String] = []
        pool.onFailure = { failures.append($0) }
        let url = try badMov()
        _ = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "A")
        _ = pool.acquire(itemID: "x", fileURL: url, settings: VideoSettings(), displayID: "B")
        await wait { !failures.isEmpty }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(failures == ["x"])
        pool.release(itemID: "x", displayID: "A")
        pool.release(itemID: "x", displayID: "B")
    }

    @Test func missingFileReportsFailure() async {
        let pool = VideoPlayerPool()
        var failures: [String] = []
        pool.onFailure = { failures.append($0) }
        _ = pool.acquire(itemID: "x", fileURL: dir.appendingPathComponent("nope.mov"),
                         settings: VideoSettings(), displayID: "A")
        await wait { !failures.isEmpty }
        #expect(failures == ["x"])
        pool.release(itemID: "x", displayID: "A")
    }

    @Test func releaseDuringLoadDropsLateResult() async throws {
        let pool = VideoPlayerPool()
        var failures: [String] = []
        pool.onFailure = { failures.append($0) }
        _ = pool.acquire(itemID: "x", fileURL: try badMov(), settings: VideoSettings(), displayID: "A")
        pool.release(itemID: "x", displayID: "A")  // before the async duration load lands
        try? await Task.sleep(for: .seconds(1))
        #expect(failures.isEmpty)
    }
}
