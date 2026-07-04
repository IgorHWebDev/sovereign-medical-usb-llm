#!/usr/bin/env bash
# verify_m4.sh — mechanical re-test of milestone m4 (auditgw).
# Exit 0 = pass. Any failed check exits nonzero with a FAIL: line.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/usb_stick/bin/mac-arm64/auditgw"
WIN="$ROOT/usb_stick/bin/win-x64/auditgw.exe"
SRC="$ROOT/src/auditgw"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

TMP="$(mktemp -d /tmp/verify_m4.XXXXXX)" || fail "cannot create temp dir"
trap 'rm -rf "$TMP"' EXIT

# --- 1. Go module: stdlib only ------------------------------------------
[ -f "$SRC/go.mod" ] || fail "src/auditgw/go.mod missing"
grep -q '^module ' "$SRC/go.mod" || fail "go.mod has no module line"
grep -q '^require' "$SRC/go.mod" && fail "go.mod declares dependencies; must be stdlib only"
ok "go module present, stdlib only"

# --- 2. Required features present in source ------------------------------
grep -rq 'X-Operator-Id' "$SRC" || fail "X-Operator-Id enforcement not found in source"
grep -rq '/api/status' "$SRC"   || fail "/api/status route not found in source"
grep -rq '/api/shutdown' "$SRC" || fail "/api/shutdown route not found in source"
grep -rq 'allow-online' "$SRC"  || fail "--allow-online flag not found in source"
grep -rq 'spawn-llm' "$SRC"     || fail "--spawn-llm flag not found in source"
grep -rq '127.0.0.1' "$SRC"     || fail "loopback binding not found in source"
ok "source implements required routes/flags"

# --- 3. Hash-chain unit tests (when a Go toolchain is available) ---------
GO_BIN="$(command -v go || true)"
[ -z "$GO_BIN" ] && [ -x /opt/homebrew/bin/go ] && GO_BIN=/opt/homebrew/bin/go
if [ -n "$GO_BIN" ]; then
  [ -f "$SRC/auditlog_test.go" ] || fail "auditlog_test.go missing"
  (cd "$SRC" && CGO_ENABLED=0 "$GO_BIN" test ./... >"$TMP/gotest.log" 2>&1) \
    || { cat "$TMP/gotest.log" >&2; fail "go test failed"; }
  ok "go unit tests pass"
else
  echo "warn: go toolchain not found; skipping unit-test run (binaries still checked)"
fi

# --- 4. Binaries exist and are the right formats --------------------------
[ -f "$MAC" ] || fail "mac-arm64/auditgw missing"
[ -x "$MAC" ] || fail "mac-arm64/auditgw not executable"
file "$MAC" | grep -q 'arm64' || fail "mac binary is not arm64: $(file "$MAC")"
[ -f "$WIN" ] || fail "win-x64/auditgw.exe missing"
file "$WIN" | grep -q 'PE32+' || fail "win binary is not PE32+: $(file "$WIN")"
file "$WIN" | grep -qi 'x86-64' || fail "win binary is not x86-64: $(file "$WIN")"
ok "binaries present: mac arm64 Mach-O + win PE32+ x86-64"

# --- 5. auditgw -h exits 0 ------------------------------------------------
"$MAC" -h >/dev/null 2>&1 || fail "auditgw -h exited nonzero"
"$MAC" --help >/dev/null 2>&1 || fail "auditgw --help exited nonzero"
ok "auditgw -h exits 0"

# --- 6. Chain: append 3 entries, verify passes ----------------------------
CHAIN="$TMP/audit-chain.jsonl"
for i in 1 2 3; do
  "$MAC" append --file "$CHAIN" --operator "op-$i" \
    --prompt "prompt $i" --response "response $i" \
    --params '{"temperature":0.7,"route":"/v1/chat/completions"}' \
    --model-file test-model.gguf --model-sha256 deadbeef --build-id verify-m4 \
    >/dev/null || fail "append $i failed"
done
LINES=$(wc -l < "$CHAIN" | tr -d ' ')
[ "$LINES" = "4" ] || fail "expected 4 lines (genesis + 3), got $LINES"
head -1 "$CHAIN" | grep -q 'verify-m4' || fail "genesis entry missing stick build id"
head -1 "$CHAIN" | grep -q '"prev_hash":"0\{64\}"' || fail "genesis prev_hash is not 64 zeros"
"$MAC" verify "$CHAIN" >/dev/null || fail "verify FAILED on an intact chain"
ok "3 entries appended after genesis; verify passes on intact chain"

# --- 7. Flip one byte in a copy: verify must FAIL on the copy -------------
COPY="$TMP/audit-tampered.jsonl"
cp "$CHAIN" "$COPY"
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
i = d.find(b"op-2")
assert i >= 0, "marker not found"
d[i] = ord("X")   # flip one byte: op-2 -> Xp-2
open(p, "wb").write(d)
' "$COPY" || fail "byte flip failed"
else
  perl -e '
local $/; open(F,"+<",$ARGV[0]) or die; my $d=<F>;
my $i=index($d,"op-2"); die "marker not found" if $i<0;
substr($d,$i,1)="X"; seek(F,0,0); print F $d; close F;
' "$COPY" || fail "byte flip failed"
fi
cmp -s "$CHAIN" "$COPY" && fail "tamper copy is identical to original"
if "$MAC" verify "$COPY" >/dev/null 2>&1; then
  fail "verify PASSED on a tampered chain — hash chain is broken"
fi
"$MAC" verify "$CHAIN" >/dev/null || fail "original chain no longer verifies"
ok "single flipped byte detected: verify fails on tampered copy, original still intact"

echo "PASS: verify_m4 — auditgw built for both OSes, hash chain tamper-evident"
exit 0
