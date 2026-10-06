import Testing
@testable import WallpaperCore

@Suite struct SystemActivityTests {
    @Test func startsActive() {
        #expect(SystemActivity().isInactive == false)
    }

    @Test func isInactiveTruthTable() {
        for bits in 0..<16 {
            let a = SystemActivity(locked: bits & 1 != 0, screensAsleep: bits & 2 != 0,
                                   sessionInactive: bits & 4 != 0, screensaver: bits & 8 != 0)
            #expect(a.isInactive == (bits != 0), "bits=\(bits)")
        }
    }

    // (on event, off event, flag keypath)
    static let pairs: [(SystemActivity.Event, SystemActivity.Event, KeyPath<SystemActivity, Bool>)] = [
        (.locked, .unlocked, \.locked),
        (.screensSlept, .screensWoke, \.screensAsleep),
        (.sessionResigned, .sessionBecameActive, \.sessionInactive),
        (.screensaverStarted, .screensaverStopped, \.screensaver),
    ]
    static let allFlags: [KeyPath<SystemActivity, Bool>] = [\.locked, \.screensAsleep, \.sessionInactive, \.screensaver]

    @Test func onEventSetsOnlyItsOwnFlag() {
        for (on, _, flag) in Self.pairs {
            var a = SystemActivity()
            a.apply(on)
            for f in Self.allFlags { #expect(a[keyPath: f] == (f == flag)) }
            #expect(a.isInactive)
        }
    }

    @Test func offEventClearsOnlyItsOwnFlag() {
        for (_, off, flag) in Self.pairs {
            var a = SystemActivity(locked: true, screensAsleep: true, sessionInactive: true, screensaver: true)
            a.apply(off)
            for f in Self.allFlags { #expect(a[keyPath: f] == (f != flag)) }
            #expect(a.isInactive)
        }
    }

    @Test func staysInactiveUntilAllCleared() {
        var a = SystemActivity()
        a.apply(.locked)
        a.apply(.screensaverStarted)
        a.apply(.unlocked)
        #expect(a.isInactive)
        a.apply(.screensaverStopped)
        #expect(a.isInactive == false)
    }

    @Test func eventsAreIdempotent() {
        var a = SystemActivity()
        a.apply(.locked); a.apply(.locked)
        a.apply(.unlocked)
        #expect(a == SystemActivity())
        a.apply(.unlocked)
        #expect(a == SystemActivity())
    }
}
