# Chaos sidecar

`chaos_action.py` asks an LLM (Featherless) for two cursed iMessages written by the pet, flips a coin, and sends the winner through Messages.

```
pip install -r requirements.txt
python3 chaos_action.py "The user ignored their pet."
```

The last stdout line is always JSON: `{"label": "...", "outcome": "..."}`.

## Env vars

| Var | Required | Notes |
|---|---|---|
| `FEATHERLESS_API_KEY` | yes* | *If missing or the LLM fails 3x, built-in fallback texts are used so the script never crashes. |
| `FEATHERLESS_MODEL` | no | default `mistralai/Mistral-Nemo-Instruct-2407` |
| `CHAOS_ARMED` | no | Unless exactly `1`, nothing is sent; it prints `[DRY RUN] would ...`. |
| `CHAOS_TEXT_ALLOWLIST` | no | Comma-separated Contacts names (default `Mateo Alado`). Each run texts one at random, at the mobile number stored in Contacts, after opening Messages on that conversation. |

Both the app and the sidecar read `~/.chaos_tamagotchi.env` (`KEY=VALUE` lines, real env vars win; keep it out of git). iMessage uses `osascript` and needs Automation permission for Contacts and Messages. Off macOS it always dry-runs.

The LLM is called in JSON mode at temperature 0.8, with lenient parsing and fallbacks. Texts are signed by the pet, and family-style openers ("Hey Grandma,") are stripped.
