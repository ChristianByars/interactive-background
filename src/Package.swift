// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "InteractiveBackground",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "WallpaperCore"),
        .target(
            name: "WallpaperEngine",
            dependencies: ["WallpaperCore"],
            resources: [.copy("Resources/Wallpapers")]
        ),
        .executableTarget(
            name: "InteractiveBackground",
            dependencies: ["WallpaperEngine", "WallpaperCore"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "WallpaperCoreTests",
            dependencies: ["WallpaperCore"],
            path: "Tests/WallpaperCoreTests"
        ),
        .testTarget(
            name: "WallpaperEngineTests",
            dependencies: ["WallpaperEngine", "WallpaperCore"],
            path: "Tests/WallpaperEngineTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
