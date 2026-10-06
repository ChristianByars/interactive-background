import Testing
@testable import WallpaperCore

@Suite struct TrimRangeTests {
    @Test func normalRange() {
        #expect(TrimRange.normalized(start: 2, end: 8, duration: 10) == 2...8)
    }

    @Test func invalidEndsDefaultToWholeVideo() {
        #expect(TrimRange.normalized(start: .nan, end: .nan, duration: 10) == nil)
        #expect(TrimRange.normalized(start: 0, end: .infinity, duration: 10) == nil)
        #expect(TrimRange.normalized(start: -.infinity, end: .infinity, duration: 10) == nil)
    }

    @Test func oneInvalidEndKeepsTheOther() {
        #expect(TrimRange.normalized(start: .nan, end: 4, duration: 10) == 0...4)
        #expect(TrimRange.normalized(start: 3, end: .nan, duration: 10) == 3...10)
        #expect(TrimRange.normalized(start: 3, end: .infinity, duration: 10) == 3...10)
    }

    @Test func clampsIntoDuration() {
        #expect(TrimRange.normalized(start: -5, end: 4, duration: 10) == 0...4)
        #expect(TrimRange.normalized(start: 3, end: 50, duration: 10) == 3...10)
        #expect(TrimRange.normalized(start: -5, end: 50, duration: 10) == nil)
    }

    @Test func invertedOrEmptyIsWholeVideo() {
        #expect(TrimRange.normalized(start: 8, end: 2, duration: 10) == nil)
        #expect(TrimRange.normalized(start: 5, end: 5, duration: 10) == nil)
        #expect(TrimRange.normalized(start: 20, end: 30, duration: 10) == nil)
    }

    @Test func tooShortIsWholeVideo() {
        #expect(TrimRange.normalized(start: 1, end: 1.05, duration: 10) == nil)
    }

    @Test func badDurationIsNil() {
        #expect(TrimRange.normalized(start: 1, end: 2, duration: 0) == nil)
        #expect(TrimRange.normalized(start: 1, end: 2, duration: .nan) == nil)
        #expect(TrimRange.normalized(start: 1, end: 2, duration: .infinity) == nil)
    }

    // MARK: Outcome of OK in the trim editor

    @Test func outcomeSavesARealTrim() {
        #expect(TrimRange.outcome(start: 2, end: 8, duration: 10) == .save(2...8))
        #expect(TrimRange.outcome(start: .nan, end: 4, duration: 10) == .save(0...4))
    }

    @Test func outcomeClearsTrimOnlyForTheWholeVideo() {
        #expect(TrimRange.outcome(start: 0, end: 10, duration: 10) == .save(nil))
        #expect(TrimRange.outcome(start: -5, end: 50, duration: 10) == .save(nil))
        #expect(TrimRange.outcome(start: .nan, end: .nan, duration: 10) == .save(nil))
        #expect(TrimRange.outcome(start: -.infinity, end: .infinity, duration: 10) == .save(nil))
    }

    @Test func outcomeKeepsExistingTrimForUnusableSelections() {
        #expect(TrimRange.outcome(start: 1, end: 1.05, duration: 10) == .keepExisting)
        #expect(TrimRange.outcome(start: 5, end: 5, duration: 10) == .keepExisting)
        #expect(TrimRange.outcome(start: 8, end: 2, duration: 10) == .keepExisting)
        #expect(TrimRange.outcome(start: 9.95, end: .nan, duration: 10) == .keepExisting)
    }

    @Test func outcomeKeepsExistingTrimForBadDuration() {
        #expect(TrimRange.outcome(start: 0, end: 10, duration: 0) == .keepExisting)
        #expect(TrimRange.outcome(start: 0, end: 10, duration: .nan) == .keepExisting)
    }
}
