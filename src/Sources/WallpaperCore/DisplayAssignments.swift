import Foundation

public typealias DisplayID = String

public enum DisplayAssignments {
    /// Resolves which wallpaper item a display shows.
    /// - Own assignment, if present, known and not missing.
    /// - An assigned-but-missing/unknown item falls back to Aurora (not to main's wallpaper).
    /// - A display with no assignment at all uses the main display's resolved choice
    ///   (same rules; Aurora if main is nil, unassigned, missing or unknown).
    public static func resolve(
        display: DisplayID,
        main: DisplayID?,
        assignments: [DisplayID: String],
        missing: Set<String>,
        knownItemIDs: Set<String>
    ) -> String {
        func usable(_ id: String) -> Bool { knownItemIDs.contains(id) && !missing.contains(id) }

        if let own = assignments[display] {
            return usable(own) ? own : WallpaperItem.auroraID
        }
        if let main, let mainChoice = assignments[main], usable(mainChoice) {
            return mainChoice
        }
        return WallpaperItem.auroraID
    }
}
