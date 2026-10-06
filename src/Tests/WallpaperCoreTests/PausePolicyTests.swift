import Testing
@testable import WallpaperCore

@Suite struct PausePolicyTests {
    @Test func isPausedTruthTable() {
        for manual in [false, true] {
            for system in [false, true] {
                for covered in [false, true] {
                    let p = PausePolicy(manualPause: manual, systemInactive: system, covered: ["d": covered])
                    #expect(p.isPaused("d") == (manual || system || covered),
                            "manual=\(manual) system=\(system) covered=\(covered)")
                }
            }
        }
    }

    @Test func unlistedDisplayIsNotCovered() {
        let p = PausePolicy(manualPause: false, systemInactive: false, covered: [:])
        #expect(p.isPaused("x") == false)
        #expect(PausePolicy(manualPause: true, systemInactive: false, covered: [:]).isPaused("x"))
    }

    @Test func defaultsPlay() {
        #expect(PausePolicy().isPaused("d") == false)
        #expect(PausePolicy().shouldPlay(displays: ["d"]))
    }

    @Test func shouldPlayTrueIfAnyDisplayUnpaused() {
        let p = PausePolicy(manualPause: false, systemInactive: false, covered: ["a": true, "b": false])
        #expect(p.shouldPlay(displays: ["a", "b"]))
        #expect(p.shouldPlay(displays: ["b"]))
        #expect(p.shouldPlay(displays: ["a"]) == false)
    }

    @Test func shouldPlayFalseWhenNoDisplays() {
        #expect(PausePolicy().shouldPlay(displays: []) == false)
    }

    @Test func shouldPlayFalseWhenGloballyPaused() {
        for (m, s) in [(true, false), (false, true), (true, true)] {
            let p = PausePolicy(manualPause: m, systemInactive: s, covered: ["a": false, "b": false])
            #expect(p.shouldPlay(displays: ["a", "b"]) == false)
        }
    }

    @Test func shouldPlayFalseWhenAllCovered() {
        let p = PausePolicy(manualPause: false, systemInactive: false, covered: ["a": true, "b": true])
        #expect(p.shouldPlay(displays: ["a", "b"]) == false)
    }
}
