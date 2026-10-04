# Manual checklist

Run on the built app: `scripts/make-app.sh`, then open `build/Interactive Background.app` from Finder.
Menu shortcuts: Pause All = option-P, Open Library = cmd-L, Quit = cmd-Q.

## Core (12 points)
- [ ] 1. No Dock icon at launch. Aurora shows behind the Finder icons, clicks pass through, nothing slides when switching Spaces.
- [ ] 2. cmd-L (menu bar) opens the Library window. The Dock and cmd-Tab icon appears with the window and goes away when it closes.
- [ ] 3. Imports:
  - [ ] H.264 `.mp4` and HEVC `.mov` import through + and through drag-and-drop.
  - [ ] A fake `.mov` shows an error banner.
  - [ ] `.mkv` is rejected as unsupported.
  - [ ] The same file twice gets " 2" in the name.
- [ ] 4. Clicking a tile applies it at once. The check mark moves in both the Library and the menu.
- [ ] 5. These survive a relaunch: Fit (fill/fit/stretch), speed (0.25 and 2.0), Sound + volume, trim (and Reset), rename. A slider moved right before cmd-Q is still saved.
- [ ] 6. option-P (also with the menu open) freezes video and Aurora on a frame, not black. Toggling again resumes.
- [ ] 7. A fullscreen app drops CPU to about 0 %. A maximized window pauses the covered display (see device-only checks).
- [ ] 8. Lock, display sleep and screensaver each pause the wallpaper and resume afterwards.
- [ ] 9. Failure handling:
  - [ ] Remove an assigned item: Aurora takes over, and its imported folder is gone.
  - [ ] Delete a video file while the app is quit: tile shows "Missing", Aurora plays.
  - [ ] Corrupt `library.json`: it is renamed to `.bad` and the videos are recovered.
- [ ] 10. Display changes:
  - [ ] A resolution change only resizes the windows.
  - [ ] A Sidecar or AirPlay display shows the main display's wallpaper and can get its own. That choice returns after reconnecting.
  - [ ] The same video on both displays plays one audio stream.
  - [ ] Covering one display does not pause the other.
- [ ] 11. `pmset -g assertions` shows no display-sleep hold from the app.
- [ ] 12. `rm -rf src/.build`, then relaunch the `.app`: Aurora still loads.

## Device-only checks added during execution
Window and activation policy
- [ ] Open Library: Dock icon appears and the window comes to front. Close it: Dock icon goes away.

Trim sheet (inspector > Edit trim...)
- [ ] The `.inline` AVPlayerView shows the trim bar with handles.
- [ ] An existing trim is pre-filled when the sheet opens.
- [ ] OK saves the range (inspector shows it, loop stays inside it). Cancel leaves the old trim.
- [ ] Escape mid-trim closes the sheet and changes nothing.

Covered behavior
- [ ] A maximized window over a display pauses that display's wallpaper (within about 2 s).
- [ ] A fullscreen app pauses the display.
- [ ] Un-maximize or leave fullscreen: wallpaper resumes, no stuck pause.
- [ ] Lock then unlock: pauses then resumes.
- [ ] Display sleep then wake: pauses then resumes.
- [ ] Screensaver start then stop: pauses then resumes.
- [ ] Screensaver into lock, then unlock: resumes once, not stuck paused.
- [ ] Fast user switching away and back: resumes.

Multi-display
- [ ] Each display can have its own wallpaper.
- [ ] Covering one display does not pause the other.
- [ ] The same video on two displays plays one audio stream.
- [ ] Attach a display while Pause All is on: the new display stays paused.

Menu bar
- [ ] Check marks update live when assigning from the Library.
- [ ] option-P works while the menu is open.

Quit
- [ ] Move a slider, then cmd-Q at once. Relaunch: the value is kept (flush on quit).

Video visuals
- [ ] Fill, fit and stretch each look right (fit letterboxes, stretch distorts).
- [ ] Speed 0.5 stays smooth across two loops.
- [ ] A trimmed loop never leaves its range.
- [ ] Sound plays with Sound on at the chosen volume, silent when off.
- [ ] Pause freezes the frame (not black).

Launch and power
- [ ] No brief pause/resume flicker at launch (about 25 ms occlusion report).
- [ ] `pmset -g assertions` shows no display-sleep hold with video playing.
