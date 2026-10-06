import SwiftUI

/// Read-only bar: the looped part of the video highlighted within the full duration.
struct TrimBar: View {
    let range: ClosedRange<Double>
    let duration: Double

    var body: some View {
        GeometryReader { geo in
            // Guard the division: callers pass a positive duration, but a bad file must never crash the UI.
            let total = max(duration, .leastNonzeroMagnitude)
            let start = min(max(range.lowerBound / total, 0), 1)
            let end = min(max(range.upperBound / total, start), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * (end - start))
                    .offset(x: geo.size.width * start)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    /// m:ss.s, rounded to tenths first so 59.96 reads 1:00.0 rather than 0:60.0.
    static func format(_ seconds: Double) -> String {
        // Hand-edited library.json can hold NaN/huge values; Int(_:) would trap on them.
        let clamped = seconds.isFinite ? min(max(seconds, 0), 359_999) : 0
        let tenths = Int((clamped * 10).rounded())
        return String(format: "%d:%04.1f", tenths / 600, Double(tenths % 600) / 10)
    }
}
