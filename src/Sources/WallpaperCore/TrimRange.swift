import Foundation

/// Turns raw trim-editor end times into a safe, stored trim.
public enum TrimRange {
    /// What OK in the trim editor should do to the stored trim.
    public enum Outcome: Equatable, Sendable {
        /// Store this trim (nil = whole video).
        case save(ClosedRange<Double>?)
        /// The selection is unusable (too short, empty or inverted): keep the existing trim.
        case keepExisting
    }

    /// `start`/`end` are seconds; NaN or infinite means "not set" (-> 0 / `duration`).
    /// Returns nil for "whole video": no real trim, a trim covering everything, or one too
    /// short to loop. Never returns NaN, infinite or inverted bounds.
    public static func normalized(start: Double, end: Double, duration: Double) -> ClosedRange<Double>? {
        guard let (lower, upper) = clamped(start: start, end: end, duration: duration),
              lower < upper else { return nil }
        return VideoSettings(trim: lower...upper).loopRange(duration: duration)
    }

    /// Like `normalized`, but only a selection that really covers the whole video means
    /// "whole video"; anything else that normalizes to nil keeps the existing trim instead
    /// of silently wiping it.
    public static func outcome(start: Double, end: Double, duration: Double) -> Outcome {
        guard let (lower, upper) = clamped(start: start, end: end, duration: duration) else {
            return .keepExisting
        }
        if let trim = normalized(start: start, end: end, duration: duration) { return .save(trim) }
        return lower <= 0 && upper >= duration ? .save(nil) : .keepExisting
    }

    private static func clamped(start: Double, end: Double, duration: Double) -> (Double, Double)? {
        guard duration.isFinite, duration > 0 else { return nil }
        let lower = start.isFinite ? min(max(start, 0), duration) : 0
        let upper = end.isFinite ? min(max(end, 0), duration) : duration
        return (lower, upper)
    }
}
