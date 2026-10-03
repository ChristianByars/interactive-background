import Foundation

/// On-disk shape of `library.json`. Built-in items are never stored.
public struct LibraryFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var items: [WallpaperItem]
    public var assignments: [DisplayID: String]

    public init(
        version: Int = LibraryFile.currentVersion,
        items: [WallpaperItem] = [],
        assignments: [DisplayID: String] = [:]
    ) {
        self.version = version
        self.items = items
        self.assignments = assignments
    }
}
