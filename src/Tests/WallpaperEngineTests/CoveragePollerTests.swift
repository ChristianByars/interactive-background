import CoreGraphics
import Foundation
import Testing
import WallpaperCore
@testable import WallpaperEngine

@Suite struct CoveragePollerTests {
    @Test func primaryDisplayFlipsToTopLeft() {
        // 1440x900 primary, menu bar 25 pt on top, Dock 70 pt at the bottom.
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 805)
        let cg = CoveragePoller.cgRect(fromAppKit: visible, primaryHeight: 900)
        #expect(cg == CGRect(x: 0, y: 25, width: 1440, height: 805))
    }

    @Test func secondaryAboveAndBelowPrimary() {
        // A display stacked above the primary has a positive AppKit y and a negative CG y.
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        #expect(CoveragePoller.cgRect(fromAppKit: above, primaryHeight: 900)
                == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let below = CGRect(x: 100, y: -1080, width: 1920, height: 1080)
        #expect(CoveragePoller.cgRect(fromAppKit: below, primaryHeight: 900)
                == CGRect(x: 100, y: 900, width: 1920, height: 1080))
    }

    @Test func tinyUsableRectIsNotPolled() {
        #expect(CoveragePoller.isUsable(CGRect(x: 0, y: 0, width: 8, height: 8)))
        #expect(!CoveragePoller.isUsable(CGRect(x: 0, y: 0, width: 7.9, height: 800)))
        #expect(!CoveragePoller.isUsable(CGRect(x: 0, y: 0, width: 800, height: 0)))
    }

    @Test func mapsWindowListEntries() {
        let bounds = CGRect(x: 10, y: 20, width: 300, height: 200).dictionaryRepresentation as NSDictionary
        let entry: [String: Any] = [
            kCGWindowBounds as String: bounds,
            kCGWindowLayer as String: 0,
            kCGWindowOwnerPID as String: Int32(321),
            kCGWindowAlpha as String: 1.0,
        ]
        let infos = CoveragePoller.windowInfos(from: [entry])
        #expect(infos == [Coverage.WindowInfo(frame: CGRect(x: 10, y: 20, width: 300, height: 200),
                                              layer: 0, ownerPID: 321, alpha: 1.0)])
    }

    @Test func skipsEntriesWithMissingOrMalformedKeys() {
        let bounds = CGRect(x: 0, y: 0, width: 10, height: 10).dictionaryRepresentation as NSDictionary
        let good: [String: Any] = [
            kCGWindowBounds as String: bounds, kCGWindowLayer as String: 25,
            kCGWindowOwnerPID as String: Int32(1), kCGWindowAlpha as String: 0.5,
        ]
        var noAlpha = good; noAlpha[kCGWindowAlpha as String] = nil
        var noPID = good; noPID[kCGWindowOwnerPID as String] = nil
        var badBounds = good; badBounds[kCGWindowBounds as String] = ["X": 1] as NSDictionary
        let infos = CoveragePoller.windowInfos(from: [noAlpha, noPID, badBounds, good])
        #expect(infos.count == 1)
        #expect(infos.first?.layer == 25)
    }

    @Test func mappedWindowsFeedCoverage() {
        let bounds = CGRect(x: 0, y: 25, width: 1440, height: 805).dictionaryRepresentation as NSDictionary
        let entry: [String: Any] = [
            kCGWindowBounds as String: bounds, kCGWindowLayer as String: 0,
            kCGWindowOwnerPID as String: Int32(99), kCGWindowAlpha as String: 1.0,
        ]
        let windows = CoveragePoller.windowInfos(from: [entry])
        let usable = CoveragePoller.cgRect(fromAppKit: CGRect(x: 0, y: 70, width: 1440, height: 805), primaryHeight: 900)
        #expect(Coverage.isCovered(displayRect: usable, windows: windows, ownPID: 1))
        #expect(!Coverage.isCovered(displayRect: usable, windows: windows, ownPID: 99))
    }
}
