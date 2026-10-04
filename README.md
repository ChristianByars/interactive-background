# Interactive Background

Animated wallpapers for macOS. A menu-bar app that draws web (HTML/WebGL) and video wallpapers behind your desktop icons, with a different wallpaper per display.

> Early prototype. Built and tested on Apple Silicon; on-device checks are still in progress ([checklist](docs/manual-checklist.md)).

## Features
- Per-display wallpapers, switchable from the menu bar or the Library window
- Import your own MP4, MOV or M4V videos (copied into the app's library)
- Per-video settings: fit (fill, fit, stretch), speed 0.25-2.0x, sound and volume, trim loop range
- Auto-pause when the desktop is covered and on sleep, lock or screensaver; Pause All with Option-P
- Built-in web wallpaper: Aurora (WebGL shader)

## Requirements
- macOS 15 or later, Apple Silicon
- Xcode command line tools (`xcode-select --install`) to build

## Build and run
```sh
scripts/make-app.sh
open "build/Interactive Background.app"
```
The app is ad-hoc signed, so the first launch may need right-click > Open. It runs from the menu bar (no Dock icon until you open the Library with Command-L).

Your library lives in `~/Library/Application Support/Interactive Background/`.

## Tests
From `src/`:
```sh
swift test
```
On a machine with only the command line tools, `swift test` may not find the Testing framework. Use:
```sh
C=/Library/Developer/CommandLineTools/Library/Developer
swift test -Xswiftc -F -Xswiftc $C/Frameworks -Xlinker -rpath -Xlinker $C/Frameworks \
  -Xlinker -rpath -Xlinker $C/usr/lib \
  -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Docs
- [Design](docs/design.md): goals, decisions, playback and import behavior
- [Architecture](docs/architecture.md): targets, storage, pause model
- [Manual checklist](docs/manual-checklist.md): checks that need a real Mac

## Not yet
Interactive wallpapers, battery-based pause, launch at login, a global pause hotkey, WebM/MKV/GIF.

## License
MIT. See [LICENSE](LICENSE).
