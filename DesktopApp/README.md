# ChaosTamagotchi (macOS app)

Menu-bar agent app (`LSUIElement`, no Dock icon) with a floating, transparent, borderless pet window.

## Open / build

```
brew install xcodegen   # only if you change project.yml
open DesktopApp/ChaosTamagotchi.xcodeproj
# or: xcodebuild -scheme ChaosTamagotchi build
```

`project.yml` is the source of truth for the project; regenerate with `xcodegen generate`. The app is unsandboxed on purpose (it runs `python3`).

## Configure

- **Sidecar path:** edit `sidecarScriptPath` at the top of `ChaosTamagotchi/PetEngine.swift`. `sidecarExtraPath` there is prepended to `PATH` so `python3` with the sidecar's dependencies is found.
- **`FEATHERLESS_API_KEY`:** must be in the app's environment. For local dev, set it in Edit Scheme > Run > Arguments > Environment Variables (the scheme already has an empty entry). Without it the pet uses canned guilt-trip lines and the sidecar falls back to built-in options.
- **Debug fast-forward:** set `CHAOS_DEBUG_DEADLINE_SECONDS=30` in the scheme to shrink the 30 minute deadline (mischief cadence scales down too). Debug only.

## Chaos Armed

Menu bar > **Chaos Armed** must be turned on manually before anything real happens. It starts **off**, in dry-run mode, on purpose: the sidecar is invoked with `CHAOS_ARMED=0` and only logs what it would have done (see the Rap Sheet).

The pet never injects keystrokes into other apps.
