import Foundation

public struct SystemActivity: Equatable, Sendable {
    public var locked: Bool
    public var screensAsleep: Bool
    public var sessionInactive: Bool
    public var screensaver: Bool

    public init(locked: Bool = false, screensAsleep: Bool = false,
                sessionInactive: Bool = false, screensaver: Bool = false) {
        self.locked = locked
        self.screensAsleep = screensAsleep
        self.sessionInactive = sessionInactive
        self.screensaver = screensaver
    }

    public var isInactive: Bool { locked || screensAsleep || sessionInactive || screensaver }

    public enum Event: CaseIterable, Sendable {
        case locked, unlocked
        case screensSlept, screensWoke
        case sessionResigned, sessionBecameActive
        case screensaverStarted, screensaverStopped
    }

    /// Each "on" event sets only its own flag; each "off" event clears only its own.
    public mutating func apply(_ event: Event) {
        switch event {
        case .locked: locked = true
        case .unlocked: locked = false
        case .screensSlept: screensAsleep = true
        case .screensWoke: screensAsleep = false
        case .sessionResigned: sessionInactive = true
        case .sessionBecameActive: sessionInactive = false
        case .screensaverStarted: screensaver = true
        case .screensaverStopped: screensaver = false
        }
    }
}
