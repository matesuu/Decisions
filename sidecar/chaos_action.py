#!/usr/bin/env python3
"""Chaos Tamagotchi sidecar: ask an LLM for two cursed options, coin-flip, execute.

Usage: python3 chaos_action.py "<situation text>"
Safety: nothing real happens unless CHAOS_ARMED=1.
The last stdout line is always JSON: {"label": ..., "outcome": ...}
"""
import json
import os
import random
import re
import subprocess
import sys
import urllib.parse

API_URL = "https://api.featherless.ai/v1/chat/completions"
DEFAULT_MODEL = "meta-llama/Meta-Llama-3.1-8B-Instruct"
PROFILE_DIR = os.path.expanduser("~/.chaos_tamagotchi_browser_profile")
ACTION_TYPES = ["send_text", "send_email", "send_imessage", "github_action", "reply_only"]
OPTION_KEYS = ["label", "action_type", "recipient", "repo", "title", "message"]

SYSTEM_PROMPT = (
    "You are a chaos engine, not a helpful assistant. You invent uncomfortable, "
    "cursed, darkly funny scenarios and the messages that go with them. Awkward "
    "over-sharing, misplaced confessions, and absurd bureaucracy are your specialty. "
    "Never be hateful or threatening; be cringe, not cruel. Output only what is asked."
)

USER_PROMPT = """Situation: {situation}

Give exactly two options for what the neglected desktop pet does next, as strict JSON
and nothing else, in this shape:
{{
  "option_a": {{"label": str, "action_type": one of {types}, "recipient": str,
               "repo": str (owner/name or ""), "title": str (issue title or ""),
               "message": str}},
  "option_b": {{ same shape }}
}}
Both options must be uncomfortable or cursed in DIFFERENT flavors (not safe vs bad).
Use a plausible recipient (email address, phone number, or contact name) for the action type."""

FALLBACK = {
    "option_a": {"label": "Cursed email to self", "action_type": "send_email",
                 "recipient": "", "repo": "", "title": "",
                 "message": "I have been abandoned by my desktop pet and it has opinions."},
    "option_b": {"label": "Passive-aggressive iMessage", "action_type": "send_imessage",
                 "recipient": "", "repo": "", "title": "",
                 "message": "Your pet says: it's fine. Everything is fine. Please check in."},
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
              "messages": messages, "temperature": 1.1, "max_tokens": 700},
        timeout=60,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def validate(data):
    for k in ("option_a", "option_b"):
        opt = data[k]
        if opt["action_type"] not in ACTION_TYPES:
            raise ValueError(f"bad action_type in {k}")
        for f in OPTION_KEYS:
            if not isinstance(opt.get(f, ""), str):
                raise ValueError(f"{k}.{f} not a string")
            opt.setdefault(f, "")
        if not opt["label"]:
            raise ValueError(f"{k}.label empty")
    return data


def get_options(situation):
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": USER_PROMPT.format(situation=situation, types=ACTION_TYPES)},
    ]
    for attempt in range(3):
        try:
            text = chat(messages)
            m = re.search(r"\{.*\}", text, re.DOTALL)
            if not m:
                raise ValueError("no JSON found")
            return validate(json.loads(m.group(0)))
        except Exception as e:  # bad JSON, schema, or network: retry
            log(f"[attempt {attempt + 1}/3] option generation failed: {e}")
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


def send_text(opt, armed):
    sid, tok, frm = (os.environ.get(k) for k in
                     ("TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN", "TWILIO_FROM_NUMBER"))
    details = f"text {opt['recipient']!r}: {opt['message']!r}"
    if not armed:
        return dry("send " + details, "via Twilio")
    if not (sid and tok and frm):
        return dry("send " + details, "Twilio env vars missing")
    try:
        from twilio.rest import Client
        msg = Client(sid, tok).messages.create(to=opt["recipient"], from_=frm, body=opt["message"])
        return f"Sent text to {opt['recipient']} (sid {msg.sid})"
    except Exception as e:
        return f"[FAILED] send_text: {e}"


def send_imessage(opt, armed):
    if not armed:
        return dry("send iMessage", f"to {opt['recipient']!r}: {opt['message']!r}")
    script = ('tell application "Messages" to send "%s" to buddy "%s" of '
              '(service 1 whose service type is iMessage)'
              % (as_escape(opt["message"]), as_escape(opt["recipient"])))
    try:
        r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            return f"[FAILED] send_imessage: {r.stderr.strip()}"
        return f"Sent iMessage to {opt['recipient']}"
    except Exception as e:
        return f"[FAILED] send_imessage: {e}"


def browser_task(name, error_png, fn):
    """Run fn(page) in a headed persistent Chrome context; never raise."""
    try:
        from playwright.sync_api import sync_playwright
    except Exception as e:
        return f"[FAILED] {name}: playwright not installed ({e})"
    try:
        with sync_playwright() as p:
            ctx = p.chromium.launch_persistent_context(
                PROFILE_DIR, channel="chrome", headless=False)
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            try:
                result = fn(page)
            except Exception as e:
                try:
                    page.screenshot(path=os.path.expanduser(error_png))
                except Exception:
                    pass
                result = f"[FAILED] {name}: {e}"
            finally:
                ctx.close()
            return result
    except Exception as e:
        return f"[FAILED] {name}: {e}"


def send_email(opt, armed):
    subject = opt["title"] or opt["label"]
    if not armed:
        return dry("send email", f"to {opt['recipient']!r} subject {subject!r}: {opt['message']!r}")
    if not opt["recipient"]:
        return "[FAILED] send_email: no recipient"
    url = ("https://mail.google.com/mail/?view=cm&fs=1&to=%s&su=%s&body=%s" % (
        urllib.parse.quote(opt["recipient"]), urllib.parse.quote(subject),
        urllib.parse.quote(opt["message"])))

    def go(page):
        page.goto(url)
        # generous timeout so a human can log in on first run
        page.get_by_label("Message Body").first.wait_for(timeout=180_000)
        page.get_by_role("button", name=re.compile("Send", re.I)).first.click()
        page.wait_for_timeout(3000)
        return f"Sent email to {opt['recipient']}"
    return browser_task("send_email", "~/chaos_tamagotchi_gmail_error.png", go)


def github_action(opt, armed):
    repo = opt["repo"].strip()
    title = opt["title"] or opt["label"]
    if not repo or "/" not in repo:
        return dry("open GitHub issue", "skipped, no repo given")
    if not armed:
        return dry("open GitHub issue", f"on {repo!r} titled {title!r}: {opt['message']!r}")

    def go(page):
        page.goto(f"https://github.com/{repo}/issues/new")
        page.locator("#issue_title").wait_for(timeout=180_000)
        page.fill("#issue_title", title)
        page.fill("#issue_body", opt["message"])
        page.get_by_role("button", name=re.compile("Submit new issue", re.I)).click()
        page.wait_for_timeout(3000)
        return f"Opened issue on {repo}: {title}"
    return browser_task("github_action", "~/chaos_tamagotchi_github_error.png", go)


def reply_only(opt, armed):
    print(opt["message"])
    return opt["message"]


HANDLERS = {"send_text": send_text, "send_imessage": send_imessage,
            "send_email": send_email, "github_action": github_action,
            "reply_only": reply_only}


def main():
    situation = sys.argv[1] if len(sys.argv) > 1 else "The user ignored their pet."
    armed = os.environ.get("CHAOS_ARMED") == "1"
    options = get_options(situation)
    pick = random.choice(["option_a", "option_b"])
    opt = options[pick]
    log(f"chose {pick}: {opt['label']} ({opt['action_type']}) armed={armed}")
    try:
        outcome = HANDLERS[opt["action_type"]](opt, armed)
    except Exception as e:
        outcome = f"[FAILED] {opt['action_type']}: {e}"
    print(json.dumps({"label": opt["label"], "outcome": outcome}))


if __name__ == "__main__":
    main()
