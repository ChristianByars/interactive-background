import CoreGraphics
import Foundation

public struct DisplayDiff: Equatable, Sendable {
    public var added: [DisplayID]
    public var removed: [DisplayID]
    public var resized: [DisplayID]

    public init(added: [DisplayID] = [], removed: [DisplayID] = [], resized: [DisplayID] = []) {
        self.added = added
        self.removed = removed
        self.resized = resized
    }

    /// Results are sorted for determinism. `resized` = same id, different frame.
    public static func compute(old: [DisplayID: CGRect], new: [DisplayID: CGRect]) -> DisplayDiff {
        DisplayDiff(
            added: new.keys.filter { old[$0] == nil }.sorted(),
            removed: old.keys.filter { new[$0] == nil }.sorted(),
            resized: new.keys.filter { id in old[id].map { $0 != new[id] } ?? false }.sorted())
    }
}
