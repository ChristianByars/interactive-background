import CoreGraphics
import Testing
@testable import WallpaperCore

@Suite struct CoverageTests {
    typealias W = Coverage.WindowInfo
    let usable = CGRect(x: 0, y: 25, width: 1920, height: 1000)
    let own: Int32 = 100

    func win(_ frame: CGRect, layer: Int = 0, pid: Int32 = 200, alpha: Double = 1.0) -> W {
        W(frame: frame, layer: layer, ownerPID: pid, alpha: alpha)
    }

    func covered(_ ws: [W]) -> Bool {
        Coverage.isCovered(displayRect: usable, windows: ws, ownPID: own)
    }

    @Test func noWindowsNotCovered() { #expect(covered([]) == false) }

    @Test func fullWindowCovers() { #expect(covered([win(usable)])) }

    @Test func largerWindowCovers() {
        #expect(covered([win(CGRect(x: -10, y: 0, width: 1940, height: 1080))]))
    }

    @Test func withinInsetToleranceCovers() {
        // 4 pt short on every side of usable still counts as covering
        #expect(covered([win(usable.insetBy(dx: 4, dy: 4))]))
    }

    @Test func beyondInsetToleranceDoesNotCover() {
        #expect(covered([win(usable.insetBy(dx: 5, dy: 5))]) == false)
    }

    @Test func ownPIDIgnored() { #expect(covered([win(usable, pid: own)]) == false) }

    @Test func nonZeroLayerIgnored() {
        #expect(covered([win(usable, layer: 25)]) == false)
        #expect(covered([win(usable, layer: -1)]) == false)
    }

    @Test func translucentIgnored() { #expect(covered([win(usable, alpha: 0.5)]) == false) }

    @Test func alphaThresholdBoundary() {
        #expect(covered([win(usable, alpha: 0.95)]))
        #expect(covered([win(usable, alpha: 0.949)]) == false)
    }

    @Test func partialOverlapDoesNotCover() {
        #expect(covered([win(CGRect(x: 0, y: 25, width: 960, height: 1000))]) == false)
    }

    @Test func tilesDoNotCombine() {
        let left = win(CGRect(x: 0, y: 25, width: 960, height: 1000))
        let right = win(CGRect(x: 960, y: 25, width: 960, height: 1000))
        #expect(covered([left, right]) == false)
    }

    @Test func oneQualifyingWindowAmongOthersCovers() {
        let ws = [win(usable, pid: own), win(usable, layer: 3), win(usable, alpha: 0.2), win(usable)]
        #expect(covered(ws))
    }
}
