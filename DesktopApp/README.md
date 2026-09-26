# ChaosTamagotchi (macOS app)

Menu-bar agent app (`LSUIElement`, no Dock icon) with a floating, transparent, borderless pet window.

## Open / build

```
brew install xcodegen   # only if you change project.yml
open DesktopApp/ChaosTamagotchi.xcodeproj
# or: xcodebuild -scheme ChaosTamagotchi build
```

`project.yml` is the source of truth for the project; regenerate with `xcodegen generate`. The app is unsandboxed on purpose (it runs `python3`).

**Signing / permissions:** ad-hoc builds lose Accessibility and Automation grants on every rebuild. Put your identity in `DesktopApp/Local.xcconfig` (gitignored, see `Signing.xcconfig`) so grants stick. On launch the app asks for Accessibility (needed for Notion notes); approve it in System Settings > Privacy & Security > Accessibility, then relaunch.

## Configure

- **Sidecar:** `sidecar/chaos_action.py` is copied into the app bundle at build time (see `project.yml`). Set `CHAOS_SIDECAR_PATH` to run a different copy. `sidecarExtraPath` in `PetEngine.swift` is prepended to `PATH` so the `python3` with `requests` is found.
- **`FEATHERLESS_API_KEY`:** put it in `~/.chaos_tamagotchi.env` (see the root README). Without it the pet uses canned guilt-trip lines and the sidecar falls back to built-in options.
- **Debug fast-forward:** set `CHAOS_DEBUG_DEADLINE_SECONDS=30` in the scheme to shrink the 5 minute deadline (mischief cadence scales down too). Debug only.

## Chaos Armed

Menu bar > **Chaos Armed** must be turned on manually before anything real happens. It now starts **on** (texts are still pinned to the allowlisted test contact); untick it for dry-run mode: the sidecar is invoked with `CHAOS_ARMED=0` and only logs what it would have done (see the Rap Sheet).

The pet never injects keystrokes into other apps.

## Mischief

Everything lives in `Mischief.swift` (plus cursor hijack and desktop-folder drag in `PetEngine.swift`). The **Do Mischief Now** submenu fires any of it on demand.

- **Poop:** 💩 panels near the pet; each click removes one. Capped at 40.
- **Sticky notes:** yellow notes roasting your frontmost app (LLM, canned fallback). Click to dismiss; max 8.
- **Window nudge:** slides the frontmost window 60-160 px via Accessibility.
- **Spotify revenge:** plays Céline Dion's "All By Myself" for 35 s, then resumes what you were playing (or pauses). Needs Automation for Spotify.
- **Wallpaper takeover:** renders a sad pet portrait to `~/Library/Application Support/ChaosTamagotchi/` and sets it on every screen. Originals saved to `~/.chaos_tamagotchi_wallpaper.txt`; feeding or **Restore Wallpaper** puts them back.
- **Desktop folder drag / scatter:** icon positions only, never files. Backup in `~/.chaos_tamagotchi_desktop_positions.txt`; **Restore Desktop Icons** undoes it. Needs Automation for Finder.
- **Cursor hijack / nudge:** no clicks or keystrokes.

The pet never injects keystrokes into other apps.
