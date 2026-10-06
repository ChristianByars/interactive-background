import Testing
@testable import WallpaperCore

@Suite struct DisplayAssignmentsTests {
    let known: Set<String> = ["a", "b", "c", WallpaperItem.auroraID]

    func resolve(_ d: DisplayID, main: DisplayID? = "M", _ assignments: [DisplayID: String],
                 missing: Set<String> = []) -> String {
        DisplayAssignments.resolve(display: d, main: main, assignments: assignments,
                                   missing: missing, knownItemIDs: known)
    }

    @Test func ownAssignmentWins() {
        #expect(resolve("D", ["D": "a", "M": "b"]) == "a")
    }

    @Test func missingOwnFallsToAuroraNotMain() {
        #expect(resolve("D", ["D": "a", "M": "b"], missing: ["a"]) == WallpaperItem.auroraID)
    }

    @Test func unknownOwnItemFallsToAurora() {
        #expect(resolve("D", ["D": "zzz", "M": "b"]) == WallpaperItem.auroraID)
    }

    @Test func unassignedDisplayUsesMain() {
        #expect(resolve("D", ["M": "b"]) == "b")
    }

    @Test func unassignedDisplayMainMissingFallsToAurora() {
        #expect(resolve("D", ["M": "b"], missing: ["b"]) == WallpaperItem.auroraID)
    }

    @Test func unassignedDisplayMainUnknownItemFallsToAurora() {
        #expect(resolve("D", ["M": "zzz"]) == WallpaperItem.auroraID)
    }

    @Test func unassignedDisplayMainUnassignedFallsToAurora() {
        #expect(resolve("D", [:]) == WallpaperItem.auroraID)
    }

    @Test func unassignedDisplayMainNilFallsToAurora() {
        #expect(resolve("D", main: nil, ["M": "b"]) == WallpaperItem.auroraID)
    }

    @Test func mainDisplayItselfUsesOwnAssignment() {
        #expect(resolve("M", ["M": "b"]) == "b")
        #expect(resolve("M", [:]) == WallpaperItem.auroraID)
        #expect(resolve("M", ["M": "b"], missing: ["b"]) == WallpaperItem.auroraID)
    }

    @Test func auroraAssignmentIsHonoured() {
        #expect(resolve("D", ["D": WallpaperItem.auroraID, "M": "b"]) == WallpaperItem.auroraID)
    }
}
