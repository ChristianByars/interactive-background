import Foundation

public enum FitMode: String, Codable, CaseIterable, Sendable {
    case fill, fit, stretch
}

public struct VideoSettings: Codable, Equatable, Sendable {
    public static let speedRange: ClosedRange<Double> = 0.25...2.0
    public static let volumeRange: ClosedRange<Double> = 0...1
    /// Trims shorter than this (seconds) are ignored for looping.
    public static let minimumLoopLength: Double = 0.1

    public var fit: FitMode
    public var speed: Double {
        didSet { speed = Self.clamp(speed, to: Self.speedRange) }
    }
    public var audioEnabled: Bool
    public var volume: Double {
        didSet { volume = Self.clamp(volume, to: Self.volumeRange) }
    }
    public var trim: ClosedRange<Double>?

    public init(
        fit: FitMode = .fill,
        speed: Double = 1.0,
        audioEnabled: Bool = false,
        volume: Double = 0.5,
        trim: ClosedRange<Double>? = nil
    ) {
        self.fit = fit
        self.speed = Self.clamp(speed, to: Self.speedRange)
        self.audioEnabled = audioEnabled
        self.volume = Self.clamp(volume, to: Self.volumeRange)
        self.trim = trim
    }

    private static func clamp(_ v: Double, to range: ClosedRange<Double>) -> Double {
        guard !v.isNaN else { return range.lowerBound }
        return min(max(v, range.lowerBound), range.upperBound)
    }

    /// The sub-range to loop, or nil to loop the whole video.
    public func loopRange(duration: Double) -> ClosedRange<Double>? {
        guard duration > 0, let trim else { return nil }
        let lower = max(trim.lowerBound, 0)
        let upper = min(trim.upperBound, duration)
        guard lower < upper else { return nil }
        if lower <= 0 && upper >= duration { return nil }
        if upper - lower < Self.minimumLoopLength { return nil }
        return lower...upper
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case fit, speed, audioEnabled, volume, trim
    }

    private struct TrimPair: Codable {
        var start: Double
        var end: Double
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fit = try c.decodeIfPresent(FitMode.self, forKey: .fit) ?? .fill
        let speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        let audio = try c.decodeIfPresent(Bool.self, forKey: .audioEnabled) ?? false
        let volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.5
        var trim: ClosedRange<Double>?
        if let pair = try c.decodeIfPresent(TrimPair.self, forKey: .trim),
           pair.start.isFinite, pair.end.isFinite, pair.start <= pair.end {
            trim = pair.start...pair.end
        }
        self.init(fit: fit, speed: speed, audioEnabled: audio, volume: volume, trim: trim)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fit, forKey: .fit)
        try c.encode(speed, forKey: .speed)
        try c.encode(audioEnabled, forKey: .audioEnabled)
        try c.encode(volume, forKey: .volume)
        if let trim {
            try c.encode(TrimPair(start: trim.lowerBound, end: trim.upperBound), forKey: .trim)
        }
    }
}
