import Foundation
import Testing
@testable import WallpaperCore

@Suite struct WallpaperItemTests {
    private func roundTrip(_ item: WallpaperItem) throws -> WallpaperItem {
        try JSONDecoder().decode(WallpaperItem.self, from: JSONEncoder().encode(item))
    }

    @Test func videoItemRoundTrip() throws {
        let item = WallpaperItem(
            id: "abc", name: "Clip", source: .video(path: "/tmp/clip.mp4"),
            settings: VideoSettings(fit: .fit, speed: 0.5, trim: 1...3))
        #expect(try roundTrip(item) == item)
    }

    @Test func webItemRoundTrip() throws {
        let item = WallpaperItem(id: "w", name: "Web", source: .web(folder: "aurora"), settings: nil)
        #expect(try roundTrip(item) == item)
    }

    @Test func auroraIsBuiltin() {
        #expect(WallpaperItem.auroraID == "builtin.aurora")
        #expect(WallpaperItem.aurora.id == WallpaperItem.auroraID)
        #expect(WallpaperItem.aurora.name == "Aurora")
        #expect(WallpaperItem.aurora.source == .web(folder: "aurora"))
        #expect(WallpaperItem.aurora.settings == nil)
        #expect(WallpaperItem.aurora.isBuiltin)
    }

    @Test func userItemIsNotBuiltin() {
        let item = WallpaperItem(id: "1234", name: "Mine", source: .video(path: "/x.mov"), settings: nil)
        #expect(!item.isBuiltin)
    }
}
