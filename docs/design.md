# Design: dashboard and video wallpapers

Status: implemented (October 2026).

## Goal
Turn the Phase 0 spike (one desktop-level window per screen hosting a `WKWebView`) into a real menu-bar app with a library window where the user picks a wallpaper **per display** and imports **their own videos** (MP4, MOV, M4V) with per-video settings.

## Decisions
- Video plays through native AVFoundation (`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`) beside the existing `WKWebView` renderer for web wallpapers.
- Layout A: display strip on top, wallpaper grid, settings panel on the right. Menu bar menu for quick switching.
- Per-display wallpapers. Settings belong to the video, not the display.
- Imports are copied into the app's library (no linking).
- Per-video settings: fit (fill/fit/stretch), speed 0.25-2.0, audio on/off + volume, trim range.
- Auto-pause: desktop covered, sleep, lock, screensaver. Plus manual Pause All. Battery pause is out of scope.
- Minimum macOS 15. Environment is Command Line Tools only (no Xcode/XCTest); use Swift Testing.
- Out of scope for now: interactive wallpapers, bundled interactive packs, battery pause, global hotkey, persisting Pause All, WebM/MKV/GIF.

## Architecture
SwiftPM package `InteractiveBackground` (`swift-tools-version:6.0`, `swiftLanguageModes: [.v5]`, `.macOS(.v15)`), dependencies App -> Engine -> Core.

- `WallpaperCore` (library; Foundation, AVFoundation, ImageIO, UniformTypeIdentifiers; no AppKit): `VideoSettings`, `WallpaperItem`, `LibraryStore`, `DisplayAssignments`, `PausePolicy`, `SystemActivity`, `DisplayDiff`, `Coverage`, `VideoImporter`, `ImportQueue`.
- `WallpaperEngine` (library; AppKit, AVFoundation, WebKit): `WallpaperWindow`, `WallpaperRenderer`, `WebRenderer`, `VideoRenderer`, `VideoPlayerPool`, `DisplayManager`, `WallpaperEngine` facade, `SystemMonitor`, `CoveragePoller`, `BuiltinResources`, `Log`.
- `InteractiveBackground` (SwiftUI executable, `Sources/App`): `MenuBarExtra`, `Window("Library")`, `AppModel` (@Observable) owned by an `AppDelegate`.
- `scripts/make-app.sh` builds `build/Interactive Background.app`.

## Storage
`~/Library/Application Support/Interactive Background/` (root injectable for tests).
`library.json` = `{version: 1, items, assignments}`; `Videos/<uuid>/<original name>` + `thumb.jpg`.
- Built-ins (`builtin.aurora`) are merged at launch and never written to JSON.
- Display wallpaper resolution: own assignment (unless missing) -> main display's wallpaper (`CGMainDisplayID`) -> Aurora.
- Display ID: `CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()` via `CFUUIDCreateString`; raw id from `screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`.
- Remove writes `builtin.aurora` explicitly for each display that used the item, then deletes the folder.
- Saves are atomic; name/settings changes debounce 0.5 s; `flush()` on terminate. Corrupt JSON -> `library.json.bad`, start fresh, re-adopt orphaned `Videos/<uuid>/` folders. Leftover `*.partial` deleted on load.

## Playback
- `VideoPlayerPool`: one `AVQueuePlayer`+`AVPlayerLooper` per item, shared by all displays showing it; plays while any attached display is unpaused; pause freezes the frame.
- Speed -> `defaultRate` (call `play()` again if playing). Audio -> `isMuted`/`volume`. Trim change -> `disableLooping()`, `removeAllItems()`, new looper on the same player.
- **Trim range must be valid:** `AVPlayerLooper` raises an uncatchable Objective-C exception if duration is 0 or the range is empty/out of bounds. Always `load(.duration)` first; use `VideoSettings.loopRange(duration:)`; intersect with `CMTimeRangeGetIntersection`.
- Playback failure (looper status / `AVPlayerItemFailedToPlayToEndTime`) -> item flagged "Can't play", its displays fall back to Aurora.
- Web pause (all reasons): overlay a `takeSnapshot` image, hide the `WKWebView`; a counter ignores late snapshots; if snapshot fails the live view stays.
- `DisplayManager` diffs screens by display UUID; only changed windows are added/removed/resized.
- `paused(display) = manualPause || systemInactive || covered[display]`. `systemInactive` = locked, screens asleep, session inactive, or screensaver. NSWorkspace notifications come from `NSWorkspace.shared.notificationCenter`; `com.apple.screenIsLocked/Unlocked` and `com.apple.screensaver.didstart/didstop` come from `DistributedNotificationCenter`. `covered = occluded || polledCovered` (occlusion via `NSWindow.didChangeOcclusionStateNotification`; poll `CGWindowListCopyWindowInfo` every 2 s only while the display is not otherwise paused).

## Import
Serial `@MainActor ImportQueue`. Steps: UTType movie check -> `AVURLAsset.load(.isPlayable,.duration,.hasProtectedContent)` and non-empty `loadTracks(withMediaType:.video)` else `notPlayable` -> free-space check (`volumeAvailableCapacityForImportantUsageKey`) -> copy to `<name>.partial` (`FileManager.copyItem`, APFS clone; progress by polling size) then rename -> thumbnail via `AVAssetImageGenerator.image(at:)` (min(1 s, duration/2), max 480 px, JPEG via ImageIO; failure = still imported) -> add to library. Duplicate names get " 2". Importing never auto-applies. Errors: `unsupportedFormat`, `notPlayable`, `insufficientSpace(needed:)`, `copyFailed(reason)`; folder deleted on any failure after creation.

## UI
- Library window (layout A): display strip; grid (click tile = apply to selected display, check on current); "+ Import" (`.fileImporter` multiple) + `.dropDestination`; progress tiles; right-click Set on All Displays / Rename / Remove; dismissible error banner; `.inspector` panel (name, fit segmented, speed slider, sound toggle + volume, loop range bar + "Edit trim..." + Reset, Remove with `.confirmationDialog`; web items show name + "Built-in").
- Trim sheet: `NSViewRepresentable` around `AVPlayerView` (`.inline`), own `AVPlayer`, `beginTrimming` when item ready and `canBeginTrimming`; read `reversePlaybackEndTime`/`forwardPlaybackEndTime` (invalid = 0/duration).
- Menu bar: per-display submenu with inline Picker check marks (flat list with one display); Pause All (option-P, works while menu open); Open Library... (cmd-L); Quit.
- Window: `.defaultLaunchBehavior(.suppressed)`, `.restorationBehavior(.disabled)`; on appear `.regular` + `NSApp.activate()`, on disappear `.accessory`.

## Environment constraints
No Xcode: no `#Preview`, `@Entry`, `@Animatable`, `import XCTest`. `@Observable` works. Tests use Swift Testing (`swift test`; if it fails, `--disable-xctest`, or `-Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`).
Built-in resources: do NOT rely on `Bundle.module` inside the `.app` (SwiftPM puts its bundle at the .app root, which breaks codesign, and falls back to an absolute `.build` path). `BuiltinResources.wallpapersRoot` checks `Bundle.main.resourceURL/Wallpapers` first, then `Bundle.module`; `make-app.sh` copies `Sources/WallpaperEngine/Resources/Wallpapers` into `Contents/Resources/`.
`preventsDisplaySleepDuringVideoPlayback` is already false on macOS; set it explicitly anyway.
