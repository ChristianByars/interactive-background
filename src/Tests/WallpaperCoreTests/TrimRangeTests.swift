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
}
