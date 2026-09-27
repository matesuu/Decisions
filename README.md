# Chaos Tamagotchi

A joke hackathon project that actually works: a desktop pet (in the spirit of Desktop Goose) wanders around your Mac and gets more annoying the longer you ignore it. It poops on your screen, leaves nonsense sticky notes, shoves your windows, hijacks your cursor, hijacks Spotify for five seconds, and opens Mommy ASMR tabs. Let it starve to 0% and, as a last resort, it opens Messages and texts your friend one LLM-written unhinged sentence.

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
| `CHAOS_STARVE_SECONDS` | `300` | How long an ignored pet takes to go from full to 0%. Lower is harsher. |
| `CHAOS_TEXT_INTERVAL_SECONDS` | `300` | Minimum gap between texts while it's at 0%. |
| `CHAOS_DEBUG_DEADLINE_SECONDS` | `300` | Speeds up or slows down how often mischief happens (e.g. `60` for testing). |
| `CHAOS_SIDECAR_PATH` | bundled copy | Run a different `chaos_action.py`, e.g. while editing it. |

Real environment variables override the file.

### Permissions

macOS asks the first time each feature runs. You can also grant them ahead of time in **System Settings > Privacy & Security**:

| Permission | Needed for |
|---|---|
| Accessibility → ChaosTamagotchi | window shoving |
| Automation → Finder | dragging desktop icons |
| Automation → Contacts, Messages | looking up your friend's number and sending the text |
| Automation → Spotify | Spotify revenge |

If a feature fails, the reason is logged to Console.app (filter for `ChaosTamagotchi`). Ad-hoc signed builds lose these grants every time you rebuild. To keep them, create `DesktopApp/Local.xcconfig` (it's gitignored) containing your signing identity:

```
CODE_SIGN_IDENTITY = <SHA-1 from `security find-identity -v -p codesigning`>
```

## How it behaves

Hunger drains faster the emptier it gets (full to 0% in 5 minutes if ignored). Each click, or **Feed (+50%)**, adds 50%.

| Mood | Fullness (reached after, if ignored) | Behavior |
|---|---|---|
| content | > 75% (0–2.5 min) | strange idle chatter, occasional 💩 and cursor boops |
| restless | 50–75% (~2.5 min) | window shoves, 3 s cursor hijack, Spotify plays a Ken Carson / OsamaSon / xaviersobased / Carti track for 5 s |
| anxious | 10–50% (~3.7 min) | adds dragging a desktop folder's icon |
| feral | 0–10% (~4.8 min) | every 30 s: a Mommy ASMR video and a Google Images tab of nonsense |
| committingCrimes | 0% (5 min) | last resort: texts someone from `CHAOS_TEXT_ALLOWLIST`, at most every 5 minutes |

- **Always:** a nonsense sticky note about once a minute, and a Mommy ASMR video every 2–4 minutes.
- **Ultimatums:** before a severe crime it may make you pick one of two in 8 s (ignore it and it does both). Some are fake-outs that end in one giant 💩.
- **Restore Everything** (⌘R): clears all poop and notes, closes the tabs it opened, and puts your windows, desktop icons and music back. Icons move but files never do, and the pet never types into other apps.
- **Safe Mode:** the pet only roams and says cute things. No hunger, notes, tabs, music or texts.
- **Try things now:** **Do Mischief Now** fires any stunt on demand, including **Text Mateo Now**, which sends a real text.
- **Chaos Armed** (on by default): untick it and the final text becomes a dry run that only logs what it would have sent.

## Website

A static site (plain HTML/CSS/JS, no build step) lives in `docs/` and is published with GitHub Pages at <https://matesuu.github.io/Decisions/> (Settings > Pages > Deploy from a branch > `main` / `/docs`). Preview it with `python3 -m http.server 8000 --directory docs`.

More detail: [`DesktopApp/README.md`](DesktopApp/README.md), [`sidecar/README.md`](sidecar/README.md).
