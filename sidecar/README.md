# Chaos sidecar

`chaos_action.py` asks an LLM (Featherless) for two cursed options, flips a coin, and executes the winner.

```
pip install -r requirements.txt
playwright install chromium
python3 chaos_action.py "The user ignored their pet."
```

The last stdout line is always JSON: `{"label": "...", "outcome": "..."}`.

## Env vars

| Var | Required | Notes |
|---|---|---|
| `FEATHERLESS_API_KEY` | yes* | *If missing or the LLM fails 3x, built-in fallback options are used so the script never crashes. |
| `FEATHERLESS_MODEL` | no | default `meta-llama/Meta-Llama-3.1-8B-Instruct` |
| `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` | no | Needed for `send_text`; otherwise it dry-runs. |
| `CHAOS_ARMED` | no | **Safety switch.** See below. |

## CHAOS_ARMED

Unless `CHAOS_ARMED` is exactly `1`, every action is a no-op that prints `[DRY RUN] would ...` and returns that string. Nothing is sent, posted, or messaged. Set `CHAOS_ARMED=1` only when you really want real emails, iMessages, texts and GitHub issues.

## First run

Email and GitHub actions drive a real, visible Chrome window (Playwright persistent profile at `~/.chaos_tamagotchi_browser_profile`; needs Google Chrome installed). The first time one fires, log in to Gmail / GitHub by hand; the session persists. Failures save a screenshot to `~/chaos_tamagotchi_gmail_error.png` (or `..._github_error.png`).

iMessage uses `osascript` and needs Automation permission for Messages.
