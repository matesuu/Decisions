# Chaos Tamagotchi

A joke hackathon project that actually works: a desktop pet (in the spirit of Desktop Goose) wanders around your Mac and gets more annoying the longer you ignore it. It poops on your screen, leaves passive-aggressive sticky notes, shoves your windows, hijacks your cursor, plays "All By Myself" on Spotify, and replaces your wallpaper. Ignore it for the full 5 minutes and it opens Messages and texts your friend an LLM-written complaint about you.

- `DesktopApp/`: native macOS menu-bar app (Swift, AppKit + SwiftUI).
- `sidecar/`: `chaos_action.py`, the Python script the app runs for the final text. It asks an LLM ([Featherless](https://featherless.ai)) for two cursed iMessages, flips a coin, looks the friend up in Contacts and sends the winner.
- `docs/`: the project website.

## Quick start (macOS)

**Requirements:** macOS 14+, Xcode 15+, Python 3.9+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Spotify and a Featherless API key are optional.

```sh
git clone https://github.com/matesuu/Decisions.git && cd Decisions

# 1. Python deps for the sidecar (use the python3 that's on your PATH)
python3 -m pip install -r sidecar/requirements.txt

# 2. Secrets and settings (never commit this file)
cat > ~/.chaos_tamagotchi.env <<'EOF'
FEATHERLESS_API_KEY=your-key-here
CHAOS_TEXT_ALLOWLIST=Friend Name
EOF

# 3. Build and run
cd DesktopApp
xcodegen generate
xcodebuild -scheme ChaosTamagotchi -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/ChaosTamagotchi.app
```

The pet shows up at the bottom of the screen, and a paw icon with a health readout appears in the menu bar. To stop it, choose **Quit** from that menu.

### Settings (`~/.chaos_tamagotchi.env`)

| Key | Default | What it does |
|---|---|---|
| `FEATHERLESS_API_KEY` | none | LLM for sticky-note roasts and texts. Without it, canned lines are used. |
| `FEATHERLESS_MODEL` | `mistralai/Mistral-Nemo-Instruct-2407` | Any Featherless chat model. |
| `CHAOS_TEXT_ALLOWLIST` | `Mateo Alado` | Comma-separated **Contacts names** the pet may text. Each crime picks one at random and texts the phone number stored in Contacts. **Change this to your own friend(s).** |
| `CHAOS_DEBUG_DEADLINE_SECONDS` | `300` | Shorten the 5 minute cycle for testing (e.g. `60`). |
| `CHAOS_SIDECAR_PATH` | bundled copy | Run a different `chaos_action.py`, e.g. while editing it. |

Real environment variables override the file.

### Permissions

macOS asks the first time each feature runs. You can also grant them ahead of time in **System Settings > Privacy & Security**:

| Permission | Needed for |
|---|---|
| Accessibility → ChaosTamagotchi | window shoving, reading the front window title |
| Automation → Finder | dragging desktop icons |
| Automation → Contacts, Messages | looking up your friend's number and sending the text |
| Automation → Spotify | Spotify revenge |

If a feature fails, the reason is shown in the **Rap Sheet** window. Ad-hoc signed builds lose these grants every time you rebuild. To keep them, create `DesktopApp/Local.xcconfig` (it's gitignored) containing your signing identity:

```
CODE_SIGN_IDENTITY = <SHA-1 from `security find-identity -v -p codesigning`>
```

## How it behaves

| Mood | Time ignored (of 5 min) | Behavior |
|---|---|---|
| content | < 25% | occasional 💩, rare cursor grab |
| restless | < 50% | cursor nudges, 💩, sticky-note roasts of the app you're in |
| anxious | < 75% | more 💩, shoves your front window, sticky notes |
| feral | < 100% | 💩 piles up (max 40) plus one of: drag a desktop folder, 3 s cursor hijack, window shove, sticky note, Spotify plays "All By Myself" (once per cycle), sad-pet wallpaper (once per cycle) |
| committingCrimes | ≥ 100% | opens Messages and texts someone from `CHAOS_TEXT_ALLOWLIST`, once per cycle |

- **Calm it down:** click the pet or choose **Feed / Check in**. This resets the timer and restores your wallpaper.
- **Poop:** each one has to be clicked away. **Clean Up All Poop** removes them all.
- **Undo:** **Restore Desktop Icons** and **Restore Wallpaper** put things back. Icons move but files never do, and the pet never types into other apps.
- **Try things now:** **Do Mischief Now** fires any stunt on demand, including **Text Mateo Now**, which sends a real text.
- **Chaos Armed** (on by default): untick it and the final text becomes a dry run that only logs what it would have sent.

## Website

A static site (plain HTML/CSS/JS, no build step) lives in `docs/` and is published with GitHub Pages at <https://matesuu.github.io/Decisions/> (Settings > Pages > Deploy from a branch > `main` / `/docs`). Preview it with `python3 -m http.server 8000 --directory docs`.

More detail: [`DesktopApp/README.md`](DesktopApp/README.md), [`sidecar/README.md`](sidecar/README.md).
