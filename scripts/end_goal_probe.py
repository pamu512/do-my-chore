#!/usr/bin/env python3
"""parent_end_goal RPC guard: accountability goes both ways."""
import json
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta

API = "http://127.0.0.1:54321"
status = json.loads(subprocess.run(
    ["supabase", "status", "-o", "json"], capture_output=True, text=True,
    check=True, cwd="/Users/pamu/Documents/GitHub/do-my-chore").stdout)
ANON = status["ANON_KEY"]
FAM = "00000000-0000-0000-0000-000000000001"
GOAL = "00000000-0000-0000-0000-0000000000b1"
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
    headers = {"apikey": ANON, "Authorization": f"Bearer {token}",
               "Content-Type": "application/json"}
    if method == "POST":
        headers["Prefer"] = "return=representation"
    req = urllib.request.Request(
        f"{API}/rest/v1/{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else []
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:160]


def rpc(token, goal_id):
    return rest("POST", "rpc/parent_end_goal", token, {"p_goal_id": goal_id})


parent = login("parent@demo")
kid = login("kid@demo")

# Idempotence: clear leftovers from earlier probe runs.
for title in ("Bike (failing demo goal)", "Sticker chart (earned)"):
    rest("DELETE", f"goals?title=eq.{urllib.parse.quote(title)}", parent)

# 1. Fresh goal, week 0: kid trivially on pace -> parent CANNOT end.
st, _ = rpc(parent, GOAL)
check("week-0 goal is protected (kid trivially on pace)", st != 200, f"got {st}")
st, rows = rest("GET", f"goals?id=eq.{GOAL}&select=status", parent)
check("Disneyland still active after refused end", rows[0]["status"] == "active")

# 2. Kid cannot end goals at all.
st, _ = rpc(kid, GOAL)
check("kid cannot call parent_end_goal", st != 200, f"got {st}")

# 3. Failing goal: created 2 weeks ago, 4-week window, zero approvals ->
#    pace 50% at week 2 with 0% earned -> parent may end it.
past = (date.today() - timedelta(days=14)).isoformat()
future = (date.today() + timedelta(days=14)).isoformat()
st, rows = rest("POST", "goals", parent, {
    "title": "Bike (failing demo goal)", "target_amount": 200,
    "goal_mode": "kid_item", "target_date": future, "allow_makeup": True,
    "created_at": f"{past}T08:00:00Z"})
failing = rows[0]["id"] if st == 201 and rows else None
check("failing goal created (backdated created_at)", st == 201 and bool(failing), f"got {st}")

st, out = rpc(parent, failing)
check("parent ends genuinely failing goal", st in (200, 204), f"got {st} {out}")
st, rows = rest("GET", f"goals?id=eq.{failing}&select=status", parent)
check("failing goal now archived", rows and rows[0]["status"] == "archived")

# 4. Earned goal is protected: 1 approval on a 1-week, 1-chore 100% goal.
st, rows = rest("POST", "goals", parent, {
    "title": "Sticker chart (earned)", "target_amount": 50,
    "goal_mode": "kid_item", "target_date": future})
earned = rows[0]["id"] if st == 201 and rows else None
assert earned, f"goal create failed {st}"
st, rows = rest("POST", "chores", parent, {
    "goal_id": earned, "title": "Tidy room", "cadence": "once",
    "weight_pct": 100, "requires_photo": False})
chore = rows[0]["id"] if st == 201 and rows else None
assert chore, f"chore create failed {st}"
st, rows = rest("POST", "chore_submissions", kid, {"chore_id": chore})
sub = rows[0]["id"] if st == 201 and rows else None
assert sub, f"submission failed {st}"
st, _ = rest("POST", "rpc/approve_chore_submission", parent, {"p_submission_id": sub})
assert st in (200, 204), f"approve failed {st}"

# kid earned 100% but elapsed 0 -> pace 0 -> on pace -> protected.
st, out = rpc(parent, earned)
check("earned goal cannot be ended even before pace window", st != 200, f"got {st}")
st, rows = rest("GET", f"goals?id=eq.{earned}&select=status", parent)
check("earned goal still active", rows[0]["status"] == "active")

print()
if failures:
    print(f"FAILED: {failures}")
    raise SystemExit(1)
print("END-GOAL GUARD OK")
