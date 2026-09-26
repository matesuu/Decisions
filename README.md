# Chaos Tamagotchi

A joke hackathon project that actually works: a desktop pet (in the spirit of Desktop Goose) roams the bottom of your screen and escalates mischief while you ignore it. Ignore it long enough and it makes an LLM-generated chaotic action against your real accounts (email, iMessage, SMS, GitHub).

- `DesktopApp/` – native macOS menu-bar app (Swift, AppKit + SwiftUI).
- `sidecar/` – `chaos_action.py`, which the app shells out to **only at the final escalation**: it asks Featherless for two cursed options, coin-flips, and executes the winner.

The app runs `python3 sidecar/chaos_action.py "<situation>"` and parses the final JSON line (`{"label", "outcome"}`) into the Rap Sheet.

| Mood | Time ignored (of 30 min) | Behavior |
|---|---|---|
| content | < 25% | idle bob, no mischief |
| restless | < 50% | nudges your cursor every ~90s |
| anxious | < 75% | cursor nudge + LLM guilt-trip line every ~60s |
| feral | < 100% | all of the above + opens a silly URL every ~30s |
| committingCrimes | ≥ 100% | fires the sidecar once per cycle |

Click the pet or use **Feed / Check in** to reset the timer.

> **`CHAOS_ARMED` defaults to off, and that's intentional.** Nothing real happens until you enable "Chaos Armed" in the menu bar.

See `sidecar/README.md` and `DesktopApp/README.md` for setup.

## Website

A static project site (plain HTML/CSS/JS, no build step) lives in `docs/` and is published with GitHub Pages at <https://matesuu.github.io/Decisions/> (Settings > Pages > Deploy from a branch > `main` / `/docs`).

Preview locally:

```
python3 -m http.server 8000 --directory docs   # then open http://localhost:8000
```
