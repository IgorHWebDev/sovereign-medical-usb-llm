#!/bin/bash
# verify_m6.sh — mechanical re-test of milestone m6 DoD (dual launchers).
# STATIC checks only (live launch is m7). Exit 0 = pass.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
ok()   { echo "ok:   $*"; }

LAUNCHERS="START_MAC.command STOP_MAC.command START_WINDOWS.bat STOP_WINDOWS.bat"

# --- DoD 1: sources exist in src/launchers and are copied to usb_stick/ -----
for f in $LAUNCHERS; do
  src="$ROOT/src/launchers/$f"
  dst="$ROOT/usb_stick/$f"
  [ -s "$src" ] || fail "missing/empty source: src/launchers/$f"
  [ -s "$dst" ] || fail "missing/empty copy: usb_stick/$f"
  if [ -s "$src" ] && [ -s "$dst" ]; then
    cmp -s "$src" "$dst" && ok "src and usb_stick copies identical: $f" \
                         || fail "src/launchers/$f differs from usb_stick/$f"
  fi
done

for f in START_MAC.command STOP_MAC.command; do
  [ -x "$ROOT/usb_stick/$f" ] && ok "executable: usb_stick/$f" \
                              || fail "usb_stick/$f not executable"
done

# --- DoD 4a: bash -n passes on the .command files ---------------------------
for f in "$ROOT/src/launchers/START_MAC.command" "$ROOT/src/launchers/STOP_MAC.command" \
         "$ROOT/usb_stick/START_MAC.command" "$ROOT/usb_stick/STOP_MAC.command"; do
  if bash -n "$f" 2>/dev/null; then ok "bash -n: ${f#$ROOT/}"
  else fail "bash -n failed: ${f#$ROOT/}"; fi
done

# --- DoD 4b: no /Users/ (or other absolute host paths) inside any launcher --
for f in $LAUNCHERS; do
  for d in src/launchers usb_stick; do
    if grep -q '/Users/' "$ROOT/$d/$f" 2>/dev/null; then
      fail "$d/$f contains /Users/ (absolute host path)"
    fi
  done
done
grep -q '/Users/' "$ROOT/usb_stick/START_MAC.command" || ok "no /Users/ in any launcher (spot check + loop above)"

# --- DoD 4c: .bat files are ASCII with CRLF line endings ---------------------
for f in START_WINDOWS.bat STOP_WINDOWS.bat; do
  for d in src/launchers usb_stick; do
    p="$ROOT/$d/$f"
    out="$(file "$p")"
    case "$out" in
      *ASCII*CRLF*) ok "file(1): $d/$f is ASCII + CRLF" ;;
      *) fail "$d/$f: file(1) says: $out (need ASCII + CRLF)" ;;
    esac
    # byte-level: pure ASCII, every LF preceded by CR, no stray CR
    if python3 - "$p" <<'PY'
import sys
b = open(sys.argv[1], "rb").read()
assert b, "empty file"
assert all(c < 128 for c in b), "non-ASCII byte present"
assert b.replace(b"\r\n", b"").count(b"\n"[0]) == 0, "bare LF found"
assert b.replace(b"\r\n", b"").count(b"\r"[0]) == 0, "stray CR found"
PY
    then ok "byte check: $d/$f pure ASCII, strict CRLF"
    else fail "$d/$f failed strict ASCII/CRLF byte check"; fi
  done
done

# --- DoD 2: Mac launcher required logic --------------------------------------
SM="$ROOT/usb_stick/START_MAC.command"
req_mac() { grep -q -- "$1" "$SM" && ok "START_MAC: $2" || fail "START_MAC missing: $2 (pattern: $1)"; }
req_mac 'cd "$(dirname "$0")'                     'resolves its own directory (relative paths)'
req_mac 'xattr -dr com.apple.quarantine'          'quarantine self-heal'
req_mac 'sysctl -n hw.memsize'                    'RAM check via sysctl hw.memsize'
req_mac '8 \* 1024 \* 1024 \* 1024'               '8 GB warn threshold'
req_mac '/dev/tcp/127.0.0.1'                      'free-port probe'
req_mac 'llm_port_range'                          'reads configured llm port range'
req_mac 'ui_port_range'                           'reads configured ui port range'
req_mac '--spawn-llm'                             'starts auditgw with --spawn-llm'
grep -q 'trap cleanup INT TERM' "$SM" && ok "START_MAC: traps INT/TERM" || fail "START_MAC: no INT/TERM trap"
grep -q '/api/status' "$SM" && ok "START_MAC: waits on health via /api/status" || fail "START_MAC: no health wait"
grep -q '"llm_reachable":true' "$SM" && ok "START_MAC: waits for llm_reachable" || fail "START_MAC: no llm readiness wait"
grep -q 'open "http://127.0.0.1:\$UI_PORT/"' "$SM" && ok "START_MAC: opens browser" || fail "START_MAC: no browser open"
grep -q 'session-end' "$SM" && grep -q 'append --file' "$SM" \
  && ok "START_MAC: writes session-end audit event via auditgw append" \
  || fail "START_MAC: no session-end audit event"
grep -q 'pkill -P' "$SM" && ok "START_MAC: kills children on shutdown fallback" || fail "START_MAC: no child-kill fallback"
grep -Eq 'http://(0\.0\.0\.0|\*)' "$SM" && fail "START_MAC: non-loopback URL" || ok "START_MAC: loopback-only URLs"

STM="$ROOT/usb_stick/STOP_MAC.command"
grep -q '/api/shutdown' "$STM" && ok "STOP_MAC: uses /api/shutdown" || fail "STOP_MAC: no /api/shutdown"
grep -q 'kill -9' "$STM" && ok "STOP_MAC: hard-kill fallback" || fail "STOP_MAC: no kill fallback"

# --- DoD 3: Windows launcher required logic ----------------------------------
SW="$ROOT/usb_stick/START_WINDOWS.bat"
req_win() { grep -q -- "$1" "$SW" && ok "START_WINDOWS: $2" || fail "START_WINDOWS missing: $2 (pattern: $1)"; }
req_win 'cd /d "%~dp0"'                'resolves its own directory'
req_win 'TotalPhysicalMemory'          'RAM check'
req_win 'LSS 8'                        '8 GB warn threshold'
req_win 'netstat -an'                  'free-port scan via netstat'
req_win '--spawn-llm'                  'auditgw --spawn-llm supervises llama-server'
req_win 'curl.exe'                     'health wait via curl.exe'
req_win '/api/status'                  'polls /api/status'
req_win 'start "" "http://127.0.0.1:%UI_PORT%/"' 'opens browser via start ""'
grep -q 'llm_port_range' "$SW" && grep -q 'ui_port_range' "$SW" \
  && ok "START_WINDOWS: uses configured port ranges" || fail "START_WINDOWS: port ranges not from config"
# .bat stays trivial: it must NOT launch llama-server itself; any start line
# mentioning llama-server must be the auditgw invocation (--llm-bin argument)
if grep -i '^ *start ' "$SW" | grep -i 'llama-server' | grep -vqi 'auditgw'; then
  fail "START_WINDOWS launches llama-server directly (auditgw must supervise)"
else
  ok "START_WINDOWS: llama-server only via auditgw --llm-bin"
fi

SPW="$ROOT/usb_stick/STOP_WINDOWS.bat"
grep -q 'curl.exe' "$SPW" && grep -q '/api/shutdown' "$SPW" \
  && ok "STOP_WINDOWS: /api/shutdown via curl.exe" || fail "STOP_WINDOWS: no curl.exe /api/shutdown"
grep -q 'taskkill /f /im auditgw.exe' "$SPW" && ok "STOP_WINDOWS: taskkill fallback" \
  || fail "STOP_WINDOWS: no taskkill fallback"

# --- cross-check: flags used by launchers exist in the shipped auditgw -------
AGW="$ROOT/usb_stick/bin/mac-arm64/auditgw"
if [ -x "$AGW" ]; then
  H="$("$AGW" -h 2>&1)"
  for flg in --spawn-llm --llm-bin --llm-args --ui-port --llm-port --audit-dir --model-file --build-id /api/shutdown /api/status; do
    case "$H" in
      *"$flg"*) ok "auditgw supports $flg" ;;
      *) fail "auditgw help does not mention $flg (launcher/gateway drift)" ;;
    esac
  done
else
  fail "usb_stick/bin/mac-arm64/auditgw missing or not executable (needed for flag cross-check)"
fi

# --- DoD: servers/URLs are 127.0.0.1 only in all launchers -------------------
if grep -E '0\.0\.0\.0' "$ROOT/usb_stick/START_MAC.command" "$ROOT/usb_stick/STOP_MAC.command" \
     "$ROOT/usb_stick/START_WINDOWS.bat" "$ROOT/usb_stick/STOP_WINDOWS.bat" >/dev/null 2>&1; then
  fail "a launcher references 0.0.0.0 (must be 127.0.0.1 only)"
else
  ok "launchers reference 127.0.0.1 only"
fi

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "verify_m6: ALL CHECKS PASSED"
  exit 0
else
  echo "verify_m6: $FAILS check(s) FAILED"
  exit 1
fi
