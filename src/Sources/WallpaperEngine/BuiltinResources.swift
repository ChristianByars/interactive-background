import Foundation

public enum BuiltinResources {
    // Inside the .app, make-app.sh copies Wallpapers into Contents/Resources.
    // Bundle.module is only the fallback (swift run / tests), since SwiftPM's bundle
    // sits at the .app root, which breaks codesign.
    public static var wallpapersRoot: URL {
        if let resources = Bundle.main.resourceURL {
            let candidate = resources.appendingPathComponent("Wallpapers", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return Bundle.module.url(forResource: "Wallpapers", withExtension: nil)!
    }

    public static func indexURL(folder: String) -> URL {
        wallpapersRoot
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("index.html")
    }
}
