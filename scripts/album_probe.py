#!/usr/bin/env python3
"""Task 6 gate: photo-assist gating + album add/delete over live HTTP."""
import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

API = "http://127.0.0.1:54321"
STATUS = json.loads(subprocess.run(
    ["supabase", "status", "-o", "json"], capture_output=True, text=True, check=True).stdout)
ANON = STATUS["ANON_KEY"]
GOAL_ID = "00000000-0000-0000-0000-0000000000b1"

failures = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}")
    if not ok:
        failures.append(name)


def login(email):
    req = urllib.request.Request(
        f"{API}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": "demo1234"}).encode(),
        headers={"apikey": ANON, "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req) as r:
        return json.load(r)["access_token"]


def rest(method, path, token, body=None):
    req = urllib.request.Request(
        f"{API}/rest/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                 "Content-Type": "application/json", "Prefer": "return=representation"},
        method=method)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else []
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}


def fn(name, body):
    req = urllib.request.Request(
        f"{API}/functions/v1/{name}",
        data=json.dumps(body).encode(),
        headers={"apikey": ANON, "Authorization": "Bearer placeholder",
                 "Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req) as r:
        return json.load(r)


parent = login("parent@demo")

# 1. photo-assist abstains for trust-based chores
r = fn("photo-assist", {"choreTitle": "Read a chapter", "image": None})
check("assist abstains on trust chore", r["suggest"] == "abstain", r.get("reason", "")[:50])

# 2. photo-assist abstains without a key even for visual chores (no crash)
r = fn("photo-assist", {"choreTitle": "Clean the play table", "image": None})
check("assist abstains gracefully without key", r["suggest"] == "abstain", r.get("reason", "")[:50])

# 3. album: parent adds from an approved submission, then deletes
st, rows = rest("POST", "album_items", parent,
                {"goal_id": GOAL_ID, "photo_url": "https://example.com/demo-table.jpg",
                 "caption": "Table sparkling"})
item = rows[0] if isinstance(rows, list) and rows else {}
check("parent adds album item", st == 201 and item.get("id"), f"id={item.get('id', '')[:8]}")

st, items = rest("GET", f"album_items?goal_id=eq.{GOAL_ID}&select=id,photo_url,caption", parent)
check("album lists items", st == 200 and len(items) == 1, f"{len(items)} item(s)")

st, _ = rest("DELETE", f"album_items?id=eq.{item['id']}", parent)
check("parent deletes album item", st in (200, 204))

st, items = rest("GET", f"album_items?goal_id=eq.{GOAL_ID}&select=id", parent)
check("album empty after delete", len(items) == 0, f"{len(items)} item(s)")

# 4. kid cannot add or delete album items (parent-only by RLS)
kid = login("kid@demo")
st, _ = rest("POST", "album_items", kid,
             {"goal_id": GOAL_ID, "photo_url": "https://example.com/sneaky.jpg"})
check("kid cannot add album item", st == 403, f"got {st}")

print()
if failures:
    print(f"FAILED: {failures}")
    sys.exit(1)
print("TASK 6 GATE OK")
