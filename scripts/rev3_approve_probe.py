#!/usr/bin/env python3
"""Rev 3 approve RPC gate: approval flips status; no ledger rows written."""
import json
import subprocess
import sys
import urllib.error
import urllib.request

API = "http://127.0.0.1:54321"
STATUS = json.loads(subprocess.run(
    ["supabase", "status", "-o", "json"], capture_output=True, text=True, check=True).stdout)
ANON = STATUS["ANON_KEY"]
BED = "00000000-0000-0000-0000-0000000000c1"
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


kid = login("kid@demo")
parent = login("parent@demo")

st, rows = rest("POST", "chore_submissions", kid,
                {"chore_id": BED, "photo_url": "probe.jpg"})
sub = rows[0] if isinstance(rows, list) and rows else {}
check("kid submits bed chore", st == 201 and sub.get("id"), f"id={sub.get('id', '')[:8]}")

st, _ = rest("POST", "rpc/approve_chore_submission", parent,
             {"p_submission_id": sub["id"]})
check("parent approves (status flip only)", st in (200, 204))

st, subs = rest("GET", f"chore_submissions?id=eq.{sub['id']}&select=status", kid)
check("submission now approved", subs and subs[0]["status"] == "approved")

st, ledger = rest("GET", "ledger_entries?select=id", kid)
check("no ledger rows minted by approvals", st == 200 and len(ledger) == 0,
      f"{len(ledger)} rows")

st, rows = rest("POST", "parent_save_entries", parent,
                {"goal_id": "00000000-0000-0000-0000-0000000000b1", "amount": 250,
                 "note": "week 1"})
check("parent logs a save", st == 201)
st, rows = rest("POST", "parent_save_entries", kid,
                {"goal_id": "00000000-0000-0000-0000-0000000000b1", "amount": 250})
check("kid cannot log saves (403)", st == 403, f"got {st}")

print()
if failures:
    print(f"FAILED: {failures}")
    sys.exit(1)
print("REV3 APPROVE GATE OK")
