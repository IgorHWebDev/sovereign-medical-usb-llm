#!/bin/bash
# verify_m1.sh — mechanical re-test of milestone m1 DoD (scaffold).
# Exit 0 = pass. Any failed assertion prints FAIL and exits 1.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0

fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
ok()   { echo "ok:   $*"; }

# --- DoD 1: required directories exist -------------------------------------
REQUIRED_DIRS=(
  "usb_stick/bin/win-x64"
  "usb_stick/bin/mac-arm64"
  "usb_stick/models"
  "usb_stick/ui"
  "usb_stick/audit"
  "usb_stick/docs/LICENSES"
  "build"
  "src/auditgw"
  "src/ui"
  "src/launchers"
  "checks"
  "downloads"
  "tests/prompts"
)
for d in "${REQUIRED_DIRS[@]}"; do
  if [ -d "$ROOT/$d" ]; then ok "dir $d"; else fail "missing directory $d"; fi
done

# --- DoD 2: GOAL.md with goal statement + milestone table -------------------
GOAL="$ROOT/GOAL.md"
if [ -s "$GOAL" ]; then
  grep -qi "medical documentation copilot" "$GOAL" || fail "GOAL.md lacks goal statement"
  grep -qE '^\|\s*id\s*\|\s*title\s*\|\s*status\s*\|' "$GOAL" || fail "GOAL.md lacks milestone table header (id/title/status)"
  for m in m0 m1 m2 m3 m4 m5 m6 m7 m8 m9; do
    grep -qE "^\|\s*$m\s*\|" "$GOAL" || fail "GOAL.md milestone table missing row $m"
  done
  ok "GOAL.md present with goal statement and milestone table"
else
  fail "GOAL.md missing or empty"
fi

# --- DoD 3: usb_stick/stick.config stub with required keys ------------------
CFG="$ROOT/usb_stick/stick.config"
if [ -s "$CFG" ]; then
  check_kv() { # key expected_value_regex
    grep -qE "^$1=$2\$" "$CFG" || fail "stick.config: expected $1=$2"
  }
  grep -qE '^default_model=.+' "$CFG" || fail "stick.config: missing default_model=<value>"
  check_kv ctx 8192
  check_kv threads auto
  grep -qE '^llm_port_range=[0-9]+-[0-9]+$' "$CFG" || fail "stick.config: missing llm_port_range=<lo>-<hi>"
  grep -qE '^ui_port_range=[0-9]+-[0-9]+$'  "$CFG" || fail "stick.config: missing ui_port_range=<lo>-<hi>"
  check_kv offline_strict true
  check_kv no_mmap true
  ok "stick.config present with required keys"
else
  fail "usb_stick/stick.config missing or empty"
fi

# --- DoD 4: README_FIRST.html placeholder ----------------------------------
RF="$ROOT/usb_stick/README_FIRST.html"
if [ -s "$RF" ]; then
  grep -qi "<html" "$RF" || fail "README_FIRST.html is not HTML"
  ok "README_FIRST.html present"
else
  fail "usb_stick/README_FIRST.html missing or empty"
fi

# --- DoD 5: this script exists and is executable ----------------------------
if [ -x "$ROOT/checks/verify_m1.sh" ]; then
  ok "checks/verify_m1.sh executable"
else
  fail "checks/verify_m1.sh not executable"
fi

# ----------------------------------------------------------------------------
if [ "$FAILS" -eq 0 ]; then
  echo "verify_m1: PASS"
  exit 0
else
  echo "verify_m1: $FAILS failure(s)"
  exit 1
fi
