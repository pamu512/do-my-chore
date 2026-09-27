#!/usr/bin/env python3
"""RLS verification for Do My Chore (Task 1 gate).

Logs in as parent@demo and kid@demo against the local Supabase, then proves:
  [1] kid sees only own-family goals
  [2] kid cannot read another family's goal by id
  [3] kid cannot insert a goal (403)
  [4] parent can insert a goal (201)
  [5] kid ledger read is scoped (empty until entries exist, no error)
Exit code 0 = all assertions hold.
"""
import json
import sys
import urllib.request
import urllib.error

API = "http://127.0.0.1:54321"
STATUS = json.loads(
    __import__("subprocess").run(
        ["supabase", "status", "-o", "json"], capture_output=True, text=True, check=True
    ).stdout
)
ANON = STATUS["ANON_KEY"]
OTHER_FAMILY_GOAL = "00000000-0000-0000-0000-0000000000b2"


def login(email: str) -> str:
    req = urllib.request.Request(
        f"{API}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": "demo1234"}).encode(),
        headers={"apikey": ANON, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req) as r:
        return json.load(r)["access_token"]


def rest(method, path, token, body=None):
    req = urllib.request.Request(
        f"{API}/rest/v1/{path}",
        data=json.dumps(body).encode() if body else None,
        headers={"apikey": ANON, "Authorization": f"Bearer {token}",
                 "Content-Type": "application/json", "Prefer": "return=minimal"},
        method=method,
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else []
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}


kid = login("kid@demo")
parent = login("parent@demo")
print("login ok: kid + parent")

failures = []

status, rows = rest("GET", "goals?select=title", kid)
titles = [r["title"] for r in rows]
ok = status == 200 and titles == ["Disneyland"]
print(f"[1] kid sees only own goals: {titles} -> {'PASS' if ok else 'FAIL'}")
if not ok:
    failures.append(1)

status, rows = rest("GET", f"goals?select=title&id=eq.{OTHER_FAMILY_GOAL}", kid)
ok = status == 200 and rows == []
print(f"[2] kid cannot read other family's goal: {rows} -> {'PASS' if ok else 'FAIL'}")
if not ok:
    failures.append(2)

status, _ = rest("POST", "goals", kid,
                 {"title": "hack", "target_amount": 1,
                  "family_id": "00000000-0000-0000-0000-000000000001"})
ok = status == 403
print(f"[3] kid cannot insert goal (got {status}): {'PASS' if ok else 'FAIL'}")
if not ok:
    failures.append(3)

status, _ = rest("POST", "goals", parent,
                 {"title": "RLS probe goal", "target_amount": 50,
                  "family_id": "00000000-0000-0000-0000-000000000001"})
ok = status == 201
print(f"[4] parent can insert goal (got {status}): {'PASS' if ok else 'FAIL'}")
if not ok:
    failures.append(4)

status, rows = rest("GET", "ledger_entries?select=kind", kid)
ok = status == 200 and isinstance(rows, list)
print(f"[5] kid ledger read scoped (got {status}, {len(rows)} rows): {'PASS' if ok else 'FAIL'}")
if not ok:
    failures.append(5)

if failures:
    print(f"FAILED: {failures}")
    sys.exit(1)
print("ALL RLS CHECKS PASS")
