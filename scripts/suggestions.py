#!/usr/bin/env python3
"""The suggestion box, from the helper's side.

Suggestions are sent from the app (Settings -> Suggestion box) to the
Firebase database built into Ablox (`CloudConfig.builtIn`), under
`suggestions/<id>`. Only one account may read them: the reader, whose uid is
`SuggestionBox.readerUID` in AbloxCore/Suggestions.swift. Its refresh token
is not in the repository; pass it as ABLOX_READER_TOKEN (or put it in
~/.ablox-reader-token).

Answers go in suggestions/replies.json, which the app reads back to show
each child what became of their idea. A reply holds the suggestion's key
and the answer, never the child's words: the repository is public.

  python3 scripts/suggestions.py list            # not answered yet, oldest first
  python3 suggestions.py list --remote           # the same without a checkout: the
                                                 # config and answers come from GitHub
  python3 scripts/suggestions.py list --all      # everything in the box
  python3 scripts/suggestions.py reply <id> done --en "Added a boat race!" --ja "ボートレースを追加したよ！" --version 1.9
  python3 scripts/suggestions.py reply <id> planned|thanks|notNow --en ... --ja ...
  python3 scripts/suggestions.py prune --days 60  # remove answered ones older than that

Only the standard library, so it runs anywhere Python 3 does.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPLIES = ROOT / "suggestions" / "replies.json"
CLOUD = ROOT / "Ablox.swiftpm" / "Sources" / "AbloxCore" / "Cloud.swift"
STATUSES = ["done", "planned", "thanks", "notNow"]
RAW = "https://raw.githubusercontent.com/prak59459-create/Ablox/HEAD/"
REMOTE = False


def read_text(local, remote_name):
    """A file from this checkout, or with --remote from GitHub."""
    if REMOTE:
        request = urllib.request.Request(RAW + remote_name, headers={"Cache-Control": "no-cache"})
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.read().decode()
    return local.read_text() if local.exists() else None


def built_in_config():
    text = read_text(CLOUD, "Ablox.swiftpm/Sources/AbloxCore/Cloud.swift") or ""
    match = re.search(r'builtIn = CloudConfig\(databaseURL: "([^"]+)",\s*apiKey: "([^"]+)"\)', text)
    if not match:
        sys.exit("Could not find CloudConfig.builtIn in Cloud.swift")
    return match.group(1).rstrip("/"), match.group(2)


def refresh_token():
    token = os.environ.get("ABLOX_READER_TOKEN", "").strip()
    if not token:
        path = Path.home() / ".ablox-reader-token"
        if path.exists():
            token = path.read_text().strip()
    if not token:
        sys.exit("No reader token: set ABLOX_READER_TOKEN (see the routine's instructions).")
    return token


def id_token(api_key):
    body = urllib.parse.urlencode({"grant_type": "refresh_token", "refresh_token": refresh_token()}).encode()
    request = urllib.request.Request(f"https://securetoken.googleapis.com/v1/token?key={api_key}", data=body)
    with urllib.request.urlopen(request, timeout=20) as response:
        answer = json.load(response)
    return answer["id_token"]


def database(method, path, token, base, body=None):
    url = f"{base}/{path}.json?auth={urllib.parse.quote(token)}"
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        if error.code in (401, 403):
            sys.exit("The database said no. Are the rules in the Firebase console the ones from "
                     "Settings -> Family -> Internet -> Copy the database rules? (" + detail + ")")
        raise
    return json.loads(raw) if raw else None


def load_replies():
    text = read_text(REPLIES, "suggestions/replies.json")
    return json.loads(text) if text else {"replies": []}


def save_replies(replies):
    REPLIES.parent.mkdir(parents=True, exist_ok=True)
    REPLIES.write_text(json.dumps(replies, ensure_ascii=False, indent=2) + "\n")


def when(millis):
    try:
        return datetime.fromtimestamp(millis / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    except Exception:
        return "?"


def command_list(args):
    base, key = built_in_config()
    token = id_token(key)
    box = database("GET", "suggestions", token, base) or {}
    answered = {reply.get("id") for reply in load_replies().get("replies", [])}
    items = sorted(box.items(), key=lambda item: item[1].get("at", 0) if isinstance(item[1], dict) else 0)
    shown = 0
    for sid, entry in items:
        if not isinstance(entry, dict):
            continue
        if not args.all and sid in answered:
            continue
        shown += 1
        print(f"--- {sid}  [{entry.get('kind', '?')}]  {when(entry.get('at', 0))}  "
              f"{entry.get('app', '?')} {entry.get('version', '?')} ({entry.get('language', '?')})"
              + ("  (answered)" if sid in answered else ""))
        print(entry.get("text", ""))
    if shown == 0:
        print("No new suggestions." if not args.all else "The box is empty.")
    else:
        print(f"\n{shown} suggestion(s).")


def command_reply(args):
    if args.status not in STATUSES:
        sys.exit(f"status must be one of {', '.join(STATUSES)}")
    if not re.fullmatch(r"s[0-9]{10,16}-[A-Z2-9]{6}", args.id):
        sys.exit("That does not look like a suggestion's key (s<digits>-<six letters>).")
    message = {}
    if args.en:
        message["en"] = args.en
    if args.ja:
        message["ja"] = args.ja
    if not message:
        sys.exit("Write an answer with --en and --ja.")
    reply = {"id": args.id, "status": args.status, "message": message}
    if args.version:
        reply["version"] = args.version
    replies = load_replies()
    replies["replies"] = [r for r in replies.get("replies", []) if r.get("id") != args.id] + [reply]
    save_replies(replies)
    print(f"Answered {args.id}: {args.status}")


def command_prune(args):
    base, key = built_in_config()
    token = id_token(key)
    box = database("GET", "suggestions", token, base) or {}
    answered = {reply.get("id") for reply in load_replies().get("replies", [])}
    cutoff = datetime.now(timezone.utc).timestamp() * 1000 - args.days * 86_400_000
    removed = 0
    for sid, entry in box.items():
        if sid in answered and isinstance(entry, dict) and entry.get("at", 0) < cutoff:
            database("DELETE", f"suggestions/{sid}", token, base)
            removed += 1
    print(f"Removed {removed} answered suggestion(s) older than {args.days} days.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    listing = sub.add_parser("list")
    listing.add_argument("--all", action="store_true")
    listing.add_argument("--remote", action="store_true")
    answering = sub.add_parser("reply")
    answering.add_argument("id")
    answering.add_argument("status")
    answering.add_argument("--en")
    answering.add_argument("--ja")
    answering.add_argument("--version")
    pruning = sub.add_parser("prune")
    pruning.add_argument("--days", type=int, default=60)
    args = parser.parse_args()
    global REMOTE
    REMOTE = getattr(args, "remote", False)
    {"list": command_list, "reply": command_reply, "prune": command_prune}[args.command](args)


if __name__ == "__main__":
    main()
