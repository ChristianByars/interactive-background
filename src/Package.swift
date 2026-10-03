// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WallpaperSpike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WallpaperSpike", path: "Sources/WallpaperSpike")
    ]
)
