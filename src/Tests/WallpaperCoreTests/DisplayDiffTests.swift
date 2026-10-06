import CoreGraphics
import Testing
@testable import WallpaperCore

@Suite struct DisplayDiffTests {
    let r1 = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let r2 = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    @Test func unchanged() {
        let d = DisplayDiff.compute(old: ["a": r1, "b": r2], new: ["a": r1, "b": r2])
        #expect(d.added.isEmpty && d.removed.isEmpty && d.resized.isEmpty)
    }

    @Test func added() {
        let d = DisplayDiff.compute(old: ["a": r1], new: ["a": r1, "b": r2])
        #expect(d.added == ["b"])
        #expect(d.removed.isEmpty && d.resized.isEmpty)
    }

    @Test func removed() {
        let d = DisplayDiff.compute(old: ["a": r1, "b": r2], new: ["a": r1])
        #expect(d.removed == ["b"])
        #expect(d.added.isEmpty && d.resized.isEmpty)
    }

    @Test func resizedSizeOrOrigin() {
        let moved = CGRect(x: 100, y: 0, width: 1920, height: 1080)
        let d = DisplayDiff.compute(old: ["a": r1, "b": r1], new: ["a": r2, "b": moved])
        #expect(d.resized == ["a", "b"])
        #expect(d.added.isEmpty && d.removed.isEmpty)
    }

    @Test func mixedAndSorted() {
        let d = DisplayDiff.compute(old: ["a": r1, "b": r1, "c": r1], new: ["b": r2, "c": r1, "z": r1, "y": r1])
        #expect(d.added == ["y", "z"])
        #expect(d.removed == ["a"])
        #expect(d.resized == ["b"])
    }

    @Test func bothEmpty() {
        let d = DisplayDiff.compute(old: [:], new: [:])
        #expect(d.added.isEmpty && d.removed.isEmpty && d.resized.isEmpty)
    }
}
