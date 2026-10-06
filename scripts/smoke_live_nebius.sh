#!/usr/bin/env bash
# Hosted suggest-plan + photo-assist smoke (matching photo, then a mismatch
# photo). Prints status, provider, model, suggest, elapsed_ms, and llm_error
# reason, base_host, status, message, and available_models when present.
# Never prints keys, tokens, or emails.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFINES="${DMC_DEFINES_FILE:-$HOME/.config/ax/tmp/dmc-supabase-defines.json}"
EVIDENCE="$ROOT/docs/evidence"
EVIDENCE_DATE="${EVIDENCE_DATE:-$(date +%Y-%m-%d)}"
PHOTO="$ROOT/app/assets/photos/dishes.jpg"
MISMATCH_PHOTO="$ROOT/app/assets/photos/bed.jpg"

if [[ ! -f "$DEFINES" ]]; then
  echo "missing defines file (DMC_DEFINES_FILE or ~/.config/ax/tmp/dmc-supabase-defines.json)" >&2
  exit 1
fi
if [[ ! -f "$PHOTO" ]]; then
  echo "missing bundled photo app/assets/photos/dishes.jpg" >&2
  exit 1
fi
if [[ ! -f "$MISMATCH_PHOTO" ]]; then
  echo "missing bundled photo app/assets/photos/bed.jpg" >&2
  exit 1
fi

SUPABASE_URL="$(jq -r '.SUPABASE_URL // empty' "$DEFINES")"
SUPABASE_ANON_KEY="$(jq -r '.SUPABASE_ANON_KEY // empty' "$DEFINES")"
missing=()
[[ -z "$SUPABASE_URL" || "$SUPABASE_URL" == "null" ]] && missing+=("SUPABASE_URL")
[[ -z "$SUPABASE_ANON_KEY" || "$SUPABASE_ANON_KEY" == "null" ]] && missing+=("SUPABASE_ANON_KEY")
if ((${#missing[@]})); then
  echo "missing ${missing[*]}" >&2
  exit 1
fi

umask 077
work="$(mktemp -d)"
cleanup() {
  rm -rf "$work"
  unset SUPABASE_ANON_KEY SUPABASE_URL || true
}
trap cleanup EXIT

sign_in() {
  local email="$1"
  local role="$2"
  local out="$3"
  local req="$work/signin-${role}.json"
  local resp="$work/signin-${role}.resp"
  local code token_line
  jq -n --arg email "$email" --arg password "demo1234" \
    '{email:$email, password:$password}' > "$req"
  code="$(curl -sS --max-time 30 -o "$resp" -w '%{http_code}' \
    -X POST "${SUPABASE_URL%/}/auth/v1/token?grant_type=password" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary @"$req" || true)"
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    code=000
  fi
  rm -f "$req"
  if [[ "$code" != "200" ]]; then
    echo "sign-in ${role} status=${code}" >&2
    rm -f "$resp"
    return 1
  fi
  if ! jq -er '.access_token' "$resp" > "$out"; then
    rm -f "$resp" "$out"
    echo "sign-in ${role} status=${code} missing access_token" >&2
    return 1
  fi
  rm -f "$resp"
  token_line="$(tr -d '\n' < "$out")"
  if [[ -z "$token_line" || "$token_line" == "null" ]]; then
    echo "sign-in ${role} status=${code} missing access_token" >&2
    return 1
  fi
  printf '%s' "$token_line" > "$out"
}

write_evidence() {
  local src="$1"
  local dest="$2"
  local status="$3"
  local elapsed_ms="$4"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ ! "$status" =~ ^[0-9]+$ ]]; then
    status=0
  fi
  if [[ ! "$elapsed_ms" =~ ^[0-9]+$ ]]; then
    elapsed_ms=0
  fi
  if jq -e 'type == "object"' "$src" >/dev/null 2>&1; then
    jq --argjson status "$status" --arg ts "$ts" --argjson elapsed "$elapsed_ms" '
      def scrub:
        if type == "object" then
          with_entries(
            select(
              ((.key | ascii_downcase) as $k
                | ($k | test("token|authorization|apikey|api_key|password|email|bearer|jwt")) | not)
            )
            | .value |= scrub
          )
        elif type == "array" then map(scrub)
        else . end;
      scrub + {http_status: $status, captured_at: $ts, elapsed_ms: $elapsed}
    ' "$src" > "$dest"
  else
    jq -n --argjson status "$status" --arg ts "$ts" --argjson elapsed "$elapsed_ms" \
      '{http_status: $status, captured_at: $ts, elapsed_ms: $elapsed, unparsed: true}' > "$dest"
  fi
}

call_fn() {
  local name="$1"
  local body_file="$2"
  local token_file="$3"
  local label="${4:-$name}"
  local resp="$work/${label}.resp"
  local timing="$work/${label}.timing"
  local meta code time_total elapsed_ms
  meta="$(curl -sS --max-time 90 -o "$resp" -w '%{http_code} %{time_total}' \
    -X POST "${SUPABASE_URL%/}/functions/v1/${name}" \
    -H "apikey: ${SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer $(tr -d '\n' < "$token_file")" \
    -H "Content-Type: application/json" \
    --data-binary @"$body_file" || true)"
  code="${meta%% *}"
  time_total="${meta#* }"
  if [[ "$code" == "$time_total" ]]; then
    time_total=0
  fi
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then
    code=000
  fi
  if [[ "$time_total" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    elapsed_ms="$(awk -v t="$time_total" 'BEGIN { printf "%d", (t * 1000) + 0.5 }')"
  else
    elapsed_ms=0
  fi
  printf '%s' "$elapsed_ms" > "$timing"
  printf '%s' "$code"
}

print_summary() {
  local name="$1"
  local file="$2"
  local status provider model elapsed llm_err
  status="$(jq -r '.http_status // "null"' "$file")"
  provider="$(jq -r '(.estimate.provider // .provider // "null")' "$file")"
  model="$(jq -r '(.model // "null")' "$file")"
  elapsed="$(jq -r '.elapsed_ms // "null"' "$file")"
  llm_err="$(jq -r '
    .llm_error as $e
    | if $e == null or ($e | type) != "object" then ""
      else
        " llm_error"
        + (if $e.reason != null then " reason=\($e.reason)" else "" end)
        + (if $e.base_host != null then " base_host=\($e.base_host)" else "" end)
        + (if ($e | has("status")) then " status=\($e.status)" else "" end)
        + (if ($e | has("message")) then " message=\($e.message)" else "" end)
        + (if ($e.available_models | type) == "array" then " available_models=" + ($e.available_models | join(",")) else "" end)
      end
  ' "$file")"
  if [[ "$name" == photo-assist* ]]; then
    local suggest
    suggest="$(jq -r '(.suggest // "null")' "$file")"
    echo "${name} status=${status} provider=${provider} model=${model} suggest=${suggest} elapsed_ms=${elapsed}${llm_err}"
  else
    echo "${name} status=${status} provider=${provider} model=${model} elapsed_ms=${elapsed}${llm_err}"
  fi
}

sign_in "parent@demo" parent "$work/parent.token"
sign_in "kid@demo" kid "$work/kid.token"
rm -f "$work/kid.token"

if date -v+98d +%Y-%m-%d >/dev/null 2>&1; then
  target_date="$(date -v+98d +%Y-%m-%d)"
else
  target_date="$(date -d '+98 days' +%Y-%m-%d)"
fi

jq -n \
  --arg goal "Lego castle set" \
  --arg targetDate "$target_date" \
  --argjson kidAge 8 \
  '{
    goalText: $goal,
    title: $goal,
    targetDate: $targetDate,
    kidAge: $kidAge,
    goalMode: "kid_item"
  }' > "$work/suggest-plan.body"

b64="$(base64 < "$PHOTO" | tr -d '\n')"
jq -n --arg choreTitle "Wash the dishes" --arg image "$b64" \
  '{choreTitle: $choreTitle, image: $image}' > "$work/photo-assist.body"
unset b64

b64="$(base64 < "$MISMATCH_PHOTO" | tr -d '\n')"
jq -n --arg choreTitle "Wash the dishes" --arg image "$b64" \
  '{choreTitle: $choreTitle, image: $image}' > "$work/photo-assist-mismatch.body"
unset b64

mkdir -p "$EVIDENCE"
sp_code="$(call_fn suggest-plan "$work/suggest-plan.body" "$work/parent.token")"
write_evidence "$work/suggest-plan.resp" "$EVIDENCE/${EVIDENCE_DATE}-suggest-plan-live.json" "$sp_code" "$(cat "$work/suggest-plan.timing")"
pa_code="$(call_fn photo-assist "$work/photo-assist.body" "$work/parent.token")"
write_evidence "$work/photo-assist.resp" "$EVIDENCE/${EVIDENCE_DATE}-photo-assist-live.json" "$pa_code" "$(cat "$work/photo-assist.timing")"
mm_code="$(call_fn photo-assist "$work/photo-assist-mismatch.body" "$work/parent.token" photo-assist-mismatch)"
write_evidence "$work/photo-assist-mismatch.resp" "$EVIDENCE/${EVIDENCE_DATE}-photo-assist-mismatch-live.json" "$mm_code" "$(cat "$work/photo-assist-mismatch.timing")"

print_summary suggest-plan "$EVIDENCE/${EVIDENCE_DATE}-suggest-plan-live.json"
print_summary photo-assist "$EVIDENCE/${EVIDENCE_DATE}-photo-assist-live.json"
print_summary photo-assist-mismatch "$EVIDENCE/${EVIDENCE_DATE}-photo-assist-mismatch-live.json"

ok=0
[[ "$sp_code" =~ ^2[0-9][0-9]$ ]] || ok=1
[[ "$pa_code" =~ ^2[0-9][0-9]$ ]] || ok=1
[[ "$mm_code" =~ ^2[0-9][0-9]$ ]] || ok=1
exit "$ok"
