import CoreMedia
import Testing
import WallpaperCore
@testable import WallpaperEngine

@Suite struct LooperRangeTests {
    private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

    @Test func zeroOrInvalidDurationIsUnplayable() {
        let settings = VideoSettings(trim: 1...2)
        #expect(LooperRange.compute(duration: .zero, settings: settings) == .unplayable)
        #expect(LooperRange.compute(duration: seconds(-1), settings: settings) == .unplayable)
        #expect(LooperRange.compute(duration: .invalid, settings: settings) == .unplayable)
        #expect(LooperRange.compute(duration: .indefinite, settings: settings) == .unplayable)
        #expect(LooperRange.compute(duration: .positiveInfinity, settings: settings) == .unplayable)
    }

    @Test func noTrimLoopsWholeItemWithInvalidRange() {
        let range = LooperRange.compute(duration: seconds(5), settings: VideoSettings())
        #expect(range == .whole)
        #expect(!range.timeRange.isValid)
    }

    @Test func trimCoveringEverythingLoopsWholeItem() {
        #expect(LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 0...5)) == .whole)
        #expect(LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 0...9)) == .whole)
    }

    @Test func trimInsideDurationIsKept() {
        let range = LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 1...3))
        guard case .trimmed(let r) = range else { Issue.record("expected trimmed, got \(range)"); return }
        #expect(r.start.seconds == 1)
        #expect(r.end.seconds == 3)
        #expect(range.timeRange == r)
    }

    @Test func trimPastEndIsClippedToDuration() {
        let duration = CMTime(value: 4, timescale: 30)  // 0.133 s at a video timescale
        let range = LooperRange.compute(duration: duration, settings: VideoSettings(trim: 0.02...10))
        guard case .trimmed(let r) = range else { Issue.record("expected trimmed, got \(range)"); return }
        #expect(r.start >= .zero)
        #expect(CMTimeRangeGetEnd(r) <= duration)
        #expect(r.duration > .zero)
    }

    @Test func trimOutsideDurationOrTooShortLoopsWholeItem() {
        #expect(LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 6...8)) == .whole)
        #expect(LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 2...2)) == .whole)
        #expect(LooperRange.compute(duration: seconds(5), settings: VideoSettings(trim: 2...2.05)) == .whole)
    }

    @Test func resultIsAlwaysInsideBounds() {
        let durations = [0.05, 0.1, 0.5, 1, 3.3, 60]
        let edges = [-1, 0, 0.01, 0.1, 0.5, 1, 2.999, 3.3, 59.95, 60, 100]
        for d in durations {
            let duration = seconds(d)
            for lower in edges {
                for upper in edges where lower <= upper {
                    let range = LooperRange.compute(duration: duration, settings: VideoSettings(trim: lower...upper))
                    guard case .trimmed(let r) = range else { continue }
                    #expect(r.start >= .zero)
                    #expect(CMTimeRangeGetEnd(r) <= duration)
                    #expect(r.duration > .zero)
                }
            }
        }
    }
}
