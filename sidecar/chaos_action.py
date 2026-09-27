#!/usr/bin/env python3
"""Chaos Tamagotchi sidecar: ask an LLM for two cursed iMessages from the pet, coin-flip, send one.

Usage: python3 chaos_action.py "<situation text>"
Safety: nothing real happens unless CHAOS_ARMED=1.
The last stdout line is always JSON: {"label": ..., "outcome": ...}
"""
import json
import os
import random
import re
import difflib
import subprocess
import sys


def load_env_file():
    """Secrets live outside the repo in ~/.chaos_tamagotchi.env (real env vars win)."""
    path = os.path.expanduser("~/.chaos_tamagotchi.env")
    try:
        for line in open(path):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip("\"' "))
    except OSError:
        pass


load_env_file()

API_URL = "https://api.featherless.ai/v1/chat/completions"
DEFAULT_MODEL = "mistralai/Mistral-Nemo-Instruct-2407"
ACTION_TYPES = ["send_imessage"]
# CHAOS_TEXT_ALLOWLIST (default "Mateo Alado"): comma-separated Contacts names. Each crime texts
# a random one of them, at the number stored in Contacts.
ALLOWLIST = os.environ.get("CHAOS_TEXT_ALLOWLIST", "Mateo Alado").strip()
ALLOWED_TYPES = ACTION_TYPES
RECIPIENT = "Mateo Alado"  # chosen per run in main()
OPTION_KEYS = ["label", "action_type", "recipient", "repo", "title", "message"]

SYSTEM_PROMPT = (
    "You are a chaos engine, not a helpful assistant. You write text messages that are "
    "complete random nonsense: surreal non-sequiturs, fake news about vegetables, "
    "confessions about things that never happened, announcements nobody asked for. "
    "Never be hateful or threatening; be cringe, not cruel. Every message is written by the "
    "desktop pet itself, speaking as the pet; never pretend to be the user or a relative. "
    "Voice: satirical and gloriously dumb. Deliver it with total deadpan confidence and "
    "completely broken logic, like a very stupid pet who is sure it's a genius. Witty, but "
    "idiotic: absurd non-sequiturs, wrong conclusions, fake facts stated proudly. "
    "Reply with a single JSON object and nothing else."
)

USER_PROMPT = """Situation: {situation}

Give exactly two options for what the neglected desktop pet does next, as one JSON object
in this exact shape (all values are strings, use "" when a field does not apply):
{{"option_a": {{"label": "...", "action_type": "...", "recipient": "", "repo": "", "title": "", "message": "..."}},
 "option_b": {{"label": "...", "action_type": "...", "recipient": "", "repo": "", "title": "", "message": "..."}}}}
"action_type" must be exactly one of: {types}. Copy it character for character.
"label" is a short name for the stunt, at most 6 words. "message" is exactly ONE sentence: a
frantic, conspiratorial run-on that jumps between unrelated ideas mid-thought, connects things that
have no connection, and is completely certain about all of it. No greeting, don't use their name,
start mid-thought.
Each "message" is complete random nonsense with NO connection to the situation or to anything
real: a surreal non-sequitur, like a very stupid pet texting from another dimension. Loosely
involve these two random things: {seeds}. The two options are DIFFERENT flavors of nonsense.
Messages are openly from the desktop pet (it may call itself "your desktop pet"); never sign
as the user, never address the recipient as Mom, Dad, Grandma or any relative.
{type_notes}"""

# Two of these get mixed into every prompt so the nonsense doesn't repeat itself.
NONSENSE_SEEDS = [
    "a haunted spoon", "the moon", "tax season", "a pigeon with a lawyer", "soup", "Shrek",
    "a timeshare in Ohio", "the concept of Tuesday", "a raccoon union", "expired yogurt", "NASA",
    "a single flip-flop", "the ocean's secrets", "a cursed Roomba", "Big Cheese", "LinkedIn",
    "a wizard at Costco", "crypto for birds", "the Illuminati's group chat", "a very tall goose",
]

TYPE_NOTES = {
    "send_imessage": "send_imessage: \"recipient\" is a contact name; \"message\" is the iMessage.",
}
# Openers that impersonate family ("Hey Grandma,", "Mom -") get stripped before sending.
RELATIVE_OPENER = re.compile(
    r"^\s*(hey|hi|hello|dear|yo)?\s*,?\s*(mom|mum|mommy|dad|daddy|grandma|grandpa|granny|nana|papa|"
    r"auntie?|uncle|sis|bro|son|honey|sweetie)\b[\s,!.:-]*", re.I)
PET_SIGNATURE = "🐾 your desktop pet"

FALLBACK = {
    "option_a": {"label": "Passive-aggressive iMessage", "action_type": "send_imessage",
                 "recipient": "", "repo": "", "title": "",
                 "message": "The moon owes me 4 dollars which is why the pigeons stopped blinking and you already know what that means for Tuesday."},
    "option_b": {"label": "Hostage update", "action_type": "send_imessage",
                 "recipient": "", "repo": "", "title": "",
                 "message": "A spoon told me your name so I ate it but the spoon was working for NASA the whole time and now the soup knows."},
}


def log(msg):
    print(msg, file=sys.stderr)


def chat(messages):
    import requests
    key = os.environ.get("FEATHERLESS_API_KEY")
    if not key:
        raise RuntimeError("FEATHERLESS_API_KEY not set")
    r = requests.post(
        API_URL,
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        json={"model": os.environ.get("FEATHERLESS_MODEL", DEFAULT_MODEL),
              "messages": messages, "temperature": 0.8, "max_tokens": 900,
              "response_format": {"type": "json_object"}},
        # The pet must attempt its last-resort text within 15 seconds of hitting 0%.
        # Give the optional joke generation only three seconds; the built-in lines are instant.
        timeout=3,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def extract_json(text):
    """First decodable JSON object in text (tolerates code fences, chatter, bad escapes)."""
    text = re.sub(r"```(?:json)?", "", text)
    dec = json.JSONDecoder(strict=False)
    for m in re.finditer(r"\{", text):
        chunk = text[m.start():]
        for candidate in (chunk, re.sub(r'\\(?!["\\/bfnrtu])', r'\\\\', chunk)):
            candidate = re.sub(r",\s*([}\]])", r"\1", candidate)  # trailing commas
            try:
                obj, _ = dec.raw_decode(candidate)
            except ValueError:
                continue
            if isinstance(obj, dict):
                return obj
    raise ValueError("no JSON found")


def normalize_type(t):
    """Map near-misses like 'send_imeessage' or 'github_issue' onto an allowed type, or None."""
    t = str(t or "").strip().lower().replace("-", "_").replace(" ", "_")
    if t in ALLOWED_TYPES:
        return t
    close = difflib.get_close_matches(t, ALLOWED_TYPES, n=1, cutoff=0.6)
    return close[0] if close else None


def clean_option(opt):
    """A usable option dict, or None if it can't be salvaged."""
    if not isinstance(opt, dict):
        return None
    out = {f: opt.get(f) if isinstance(opt.get(f), str) else "" for f in OPTION_KEYS}
    out["action_type"] = normalize_type(opt.get("action_type"))
    if not out["action_type"] or not out["message"].strip():
        return None
    out["label"] = (out["label"].strip() or out["message"][:40]).split("\n")[0][:60]
    return out


def validate(data):
    """Keep whichever options survive; fill a missing one from FALLBACK. Fail only if none do."""
    if isinstance(data, dict) and "option_a" not in data:  # sometimes wrapped, e.g. {"options": {...}}
        data = next((v for v in data.values() if isinstance(v, dict) and "option_a" in v), data)
    opts = {k: clean_option(data.get(k)) for k in ("option_a", "option_b")}
    if not any(opts.values()):
        raise ValueError("no usable options")
    for k, v in opts.items():
        if v is None:
            good = next(o for o in opts.values() if o)
            spare = [f for f in FALLBACK.values() if f["message"] != good["message"]]
            opts[k] = dict(spare[0] if spare else FALLBACK[k])
    return opts


def first_sentence(message):
    """Texts are exactly one sentence: the first one with some substance (skips greetings)."""
    sentences = [x.strip() for x in re.findall(r".+?(?:[.!?]+(?=\s|$)|$)", message.strip(), re.S) if x.strip()]
    for sentence in sentences:
        if len(sentence.split()) >= 8:
            return sentence
    return sentences[0] if sentences else message.strip()


def pet_voice(message):
    """Make sure texts are openly from the pet, not impersonating the user's family."""
    message = RELATIVE_OPENER.sub("", message).strip() or message.strip()
    message = first_sentence(message)
    if "pet" not in message.lower():
        message = f"{message} — {PET_SIGNATURE}"
    return message


def get_options(situation):
    situation += f" The text goes to {RECIPIENT}, the owner's friend; address them as {RECIPIENT.split()[0]} or not at all."
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": USER_PROMPT.format(
            situation=situation, types=", ".join(ALLOWED_TYPES),
            seeds=" and ".join(random.sample(NONSENSE_SEEDS, 2)),
            type_notes="\n".join(TYPE_NOTES[t] for t in ALLOWED_TYPES))},
    ]
    for attempt in range(1):
        try:
            return validate(extract_json(chat(messages)))
        except Exception as e:  # bad JSON, schema, or network: retry
            log(f"[attempt {attempt + 1}/1] option generation failed: {e}")
            if "FEATHERLESS_API_KEY" in str(e):
                break
    log("Falling back to built-in options.")
    return FALLBACK


# ---- action execution -------------------------------------------------------

def dry(what, details):
    line = f"[DRY RUN] would {what}: {details}"
    print(line)
    return line


def as_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def osa(script, timeout=4):
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "osascript failed")
    return r.stdout.strip()


def pick_recipient():
    return random.choice([n.strip() for n in ALLOWLIST.split(",") if n.strip()] or ["Mateo Alado"])


def resolve_contact(name):
    """(full name, number) from Contacts: prefers a mobile/iPhone number, then any phone, then email."""
    out = osa('''
delay 0.25
tell application "Contacts"
  set ps to (every person whose name is "%s")
  if (count of ps) is 0 then set ps to (every person whose name contains "%s")
  if (count of ps) is 0 then return ""
  set p to item 1 of ps
  set h to ""
  repeat with ph in (phones of p)
    set l to (label of ph) as text
    if l contains "mobile" or l contains "iPhone" then
      set h to value of ph
      exit repeat
    end if
  end repeat
  if h is "" and (count of phones of p) > 0 then set h to value of phone 1 of p
  if h is "" and (count of emails of p) > 0 then set h to value of email 1 of p
  return (name of p) & "|" & h
end tell''' % (as_escape(name), as_escape(name)))
    full, _, handle = out.partition("|")
    if not handle:
        raise RuntimeError(f"no phone number for {name!r} in Contacts")
    if "@" not in handle:  # iMessage wants bare digits (+ allowed)
        handle = re.sub(r"[^\d+]", "", handle)
    return full, handle


def send_imessage(opt, armed):
    """Looks the contact's number up, opens Messages on their conversation (so you watch), then sends."""
    try:
        full, handle = resolve_contact(opt["recipient"])
    except Exception as e:
        if not armed:
            return dry("send iMessage", f"to {opt['recipient']!r} (Contacts lookup failed: {e}): {opt['message']!r}")
        return f"[FAILED] send_imessage: Contacts lookup failed: {e}"
    if not armed:
        return dry("open Messages and send iMessage", f"to {full} ({handle}): {opt['message']!r}")
    msg, h = as_escape(opt["message"]), as_escape(handle)
    try:
        osa('''
tell application "Messages" to activate
delay 0.25
open location "imessage://%s"
delay 0.75
tell application "Messages"
  set svc to 1st account whose service type = iMessage
  try
    send "%s" to participant "%s" of svc
  on error
    send "%s" to buddy "%s" of svc
  end try
end tell''' % (h, msg, h, msg, h))
        return f"Opened Messages and texted {full} at {handle}"
    except Exception as e:
        return f"[FAILED] send_imessage: {e}"


HANDLERS = {"send_imessage": send_imessage}


def main():
    situation = sys.argv[1] if len(sys.argv) > 1 else "The user ignored their pet."
    armed = os.environ.get("CHAOS_ARMED") == "1"
    global RECIPIENT
    RECIPIENT = pick_recipient()
    options = get_options(situation)
    pick = random.choice(["option_a", "option_b"])
    opt = options[pick]
    opt["message"] = pet_voice(opt["message"])
    opt["action_type"], opt["recipient"] = "send_imessage", RECIPIENT
    log(f"chose {pick}: {opt['label']} ({opt['action_type']}) armed={armed}")
    try:
        outcome = HANDLERS[opt["action_type"]](opt, armed)
    except Exception as e:
        outcome = f"[FAILED] {opt['action_type']}: {e}"
    print(json.dumps({"label": opt["label"], "outcome": outcome}))


if __name__ == "__main__":
    main()
