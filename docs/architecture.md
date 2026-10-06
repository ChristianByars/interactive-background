# Architecture

## Targets (SwiftPM, `src/`)
- `WallpaperCore`: models and pure logic, no AppKit. Settings, library store, import, pause policy, coverage, display diffing.
- `WallpaperEngine`: windows, renderers and system monitors. Depends on Core.
- `InteractiveBackground`: SwiftUI menu-bar app and Library window. Depends on both.

## How it fits together
One borderless window per display at the desktop window level (behind Finder icons), click-through, on all Spaces. Each window hosts a renderer: `WebRenderer` (WKWebView) or `VideoRenderer` (AVPlayerLayer). `WallpaperEngine` is the facade the app talks to.

## Storage
`~/Library/Application Support/Interactive Background/` (override for tests and smoke runs: `IB_LIBRARY_ROOT`).
- `library.json`: items and per-display assignments, written atomically; name and setting changes are saved after a short debounce and on quit.
- `Videos/<uuid>/`: the imported file and `thumb.jpg`.
- A corrupt or unreadable `library.json` is moved to `library.json.bad`, and orphaned video folders are re-adopted. Built-in wallpapers are never written to the file.

## Wallpaper per display
A display uses its own assignment, otherwise the main display's wallpaper, otherwise Aurora. Displays are keyed by display UUID.

## Video playback
One `AVQueuePlayer` + `AVPlayerLooper` per video, shared by every display showing it (one audio stream). `AVPlayerLooper` raises an uncatchable Objective-C exception on an empty or out-of-range time range, so the loop range is always computed first from the loaded duration (`VideoSettings.loopRange(duration:)`).

## Pause
Per display: `manual (Option-P) || system (lock, sleep, screensaver, session switch) || covered`. Covered means the window is occluded or a 2 s `CGWindowList` poll finds a full-opacity window over the display's usable area (the poll runs only while the display is not otherwise paused). Web wallpapers pause by overlaying a snapshot and hiding the web view; video pauses on the current frame.

## Packaging
`scripts/make-app.sh` builds `build/Interactive Background.app`, ad-hoc signed. Built-in wallpapers are copied to `Contents/Resources/Wallpapers` and found through `Bundle.main`, so the app does not depend on `Bundle.module` or the `.build` directory.

## Decisions
- Native AVFoundation video beside the web renderer, rather than video inside a web view.
- Imports are copied into the library (no links to files that can move).
- Minimum macOS 15.
