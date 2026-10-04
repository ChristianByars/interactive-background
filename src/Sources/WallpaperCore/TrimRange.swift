import Foundation

/// Turns raw trim-editor end times into a safe, stored trim.
public enum TrimRange {
    /// `start`/`end` are seconds; NaN or infinite means "not set" (-> 0 / `duration`).
    /// Returns nil for "whole video": no real trim, a trim covering everything, or one too
    /// short to loop. Never returns NaN, infinite or inverted bounds.
    public static func normalized(start: Double, end: Double, duration: Double) -> ClosedRange<Double>? {
        guard duration.isFinite, duration > 0 else { return nil }
        let lower = start.isFinite ? min(max(start, 0), duration) : 0
        let upper = end.isFinite ? min(max(end, 0), duration) : duration
        guard lower < upper else { return nil }
        return VideoSettings(trim: lower...upper).loopRange(duration: duration)
    }
}
