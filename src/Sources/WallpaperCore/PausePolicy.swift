import Foundation

public struct PausePolicy: Equatable, Sendable {
    public var manualPause: Bool
    public var systemInactive: Bool
    public var covered: [DisplayID: Bool]

    public init(manualPause: Bool = false, systemInactive: Bool = false, covered: [DisplayID: Bool] = [:]) {
        self.manualPause = manualPause
        self.systemInactive = systemInactive
        self.covered = covered
    }

    public func isPaused(_ d: DisplayID) -> Bool {
        manualPause || systemInactive || (covered[d] ?? false)
    }

    /// True if any listed display is unpaused.
    public func shouldPlay(displays: [DisplayID]) -> Bool {
        displays.contains { !isPaused($0) }
    }
}
