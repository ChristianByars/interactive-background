import Foundation
import Testing
@testable import WallpaperCore

@Suite struct VideoSettingsTests {
    private func decode(_ json: String) throws -> VideoSettings {
        try JSONDecoder().decode(VideoSettings.self, from: Data(json.utf8))
    }

    @Test func defaults() {
        let s = VideoSettings()
        #expect(s.fit == .fill)
        #expect(s.speed == 1.0)
        #expect(s.audioEnabled == false)
        #expect(s.volume == 0.5)
        #expect(s.trim == nil)
    }

    @Test func clampsInInit() {
        let s = VideoSettings(speed: 5, volume: 3)
        #expect(s.speed == 2.0)
        #expect(s.volume == 1.0)
        let t = VideoSettings(speed: 0.1, volume: -1)
        #expect(t.speed == 0.25)
        #expect(t.volume == 0.0)
    }

    @Test func clampsInSetter() {
        var s = VideoSettings()
        s.speed = 10
        #expect(s.speed == 2.0)
        s.speed = 0
        #expect(s.speed == 0.25)
        s.volume = 2
        #expect(s.volume == 1.0)
        s.volume = -0.5
        #expect(s.volume == 0.0)
    }

    @Test func clampsWhenDecoding() throws {
        let a = try decode(#"{"speed":5,"volume":3}"#)
        #expect(a.speed == 2.0)
        #expect(a.volume == 1.0)
        let b = try decode(#"{"speed":0.1,"volume":-1}"#)
        #expect(b.speed == 0.25)
        #expect(b.volume == 0.0)
    }

    @Test func decodesMissingKeysWithDefaults() throws {
        let empty = try decode("{}")
        #expect(empty == VideoSettings())
        let partial = try decode(#"{"fit":"stretch","audioEnabled":true}"#)
        #expect(partial.fit == .stretch)
        #expect(partial.audioEnabled == true)
        #expect(partial.speed == 1.0)
        #expect(partial.volume == 0.5)
        #expect(partial.trim == nil)
    }

    @Test func roundTripWithTrim() throws {
        let s = VideoSettings(fit: .fit, speed: 1.5, audioEnabled: true, volume: 0.8, trim: 2.0...9.5)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(VideoSettings.self, from: data)
        #expect(back == s)
        #expect(back.trim == 2.0...9.5)
    }

    @Test func roundTripWithoutTrim() throws {
        let s = VideoSettings()
        let back = try JSONDecoder().decode(VideoSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.trim == nil)
    }

    @Test func encodesTrimAsStartEndObject() throws {
        let s = VideoSettings(trim: 1.0...4.0)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        let trim = obj?["trim"] as? [String: Double]
        #expect(trim?["start"] == 1.0)
        #expect(trim?["end"] == 4.0)
    }

    @Test func decodesTrimObject() throws {
        let s = try decode(#"{"trim":{"start":3,"end":7}}"#)
        #expect(s.trim == 3.0...7.0)
    }

    @Test func loopRangeNilWithoutTrim() {
        #expect(VideoSettings().loopRange(duration: 60) == nil)
    }

    @Test func loopRangeNilWhenCoversWholeVideo() {
        #expect(VideoSettings(trim: 0...60).loopRange(duration: 60) == nil)
        #expect(VideoSettings(trim: (-5)...100).loopRange(duration: 60) == nil)
    }

    @Test func loopRangeNilWhenTooShort() {
        #expect(VideoSettings(trim: 5.0...5.05).loopRange(duration: 60) == nil)
    }

    @Test func loopRangeReturnsRange() {
        #expect(VideoSettings(trim: 10...20).loopRange(duration: 60) == 10.0...20.0)
    }

    @Test func loopRangeClampsToDuration() {
        #expect(VideoSettings(trim: 50...100).loopRange(duration: 60) == 50.0...60.0)
        #expect(VideoSettings(trim: (-10)...20).loopRange(duration: 60) == 0.0...20.0)
    }

    @Test func loopRangeNilForNonPositiveDuration() {
        #expect(VideoSettings(trim: 1...2).loopRange(duration: 0) == nil)
        #expect(VideoSettings(trim: 1...2).loopRange(duration: -3) == nil)
    }
}
