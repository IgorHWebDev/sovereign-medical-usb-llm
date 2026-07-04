#!/bin/bash
# STOP_MAC.command -- graceful shutdown of the med-usb stack on macOS.
# Asks auditgw to shut down via POST /api/shutdown (auditgw then stops the
# llama-server it supervises). Hard-kill fallback if it does not exit.
# No installation, no admin rights; relative paths only; 127.0.0.1 only.

set -u

STICK="$(cd "$(dirname "$0")" && pwd)"
cd "$STICK" || { echo "ERROR: cannot cd to stick root"; exit 1; }

cfg() { sed -n "s/^$1=//p" stick.config 2>/dev/null | head -n 1; }
UI_RANGE="$(cfg ui_port_range)"; [ -n "$UI_RANGE" ] || UI_RANGE=8180-8199
LO="${UI_RANGE%-*}"; HI="${UI_RANGE#*-}"

SESSION_PORT=""
SESSION_PID=""
if [ -f audit/session-mac.env ]; then
  SESSION_PORT="$(sed -n 's/^ui_port=//p' audit/session-mac.env | head -n 1)"
  SESSION_PID="$(sed -n 's/^pid=//p' audit/session-mac.env | head -n 1)"
fi

stop_port() {
  # only talk to services that identify themselves as auditgw
  if curl -s -m 2 "http://127.0.0.1:$1/api/status" 2>/dev/null | grep -q '"service":"auditgw"'; then
    echo "sending shutdown to auditgw on port $1 ..."
    curl -s -m 3 -X POST "http://127.0.0.1:$1/api/shutdown" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

FOUND=0
if [ -n "$SESSION_PORT" ] && stop_port "$SESSION_PORT"; then
  FOUND=1
fi
if [ "$FOUND" = "0" ]; then
  for ((p = LO; p <= HI; p++)); do
    if stop_port "$p"; then FOUND=1; fi
  done
fi
if [ "$FOUND" = "0" ]; then
  echo "no running auditgw found on ports $UI_RANGE."
fi

# hard fallback: make sure the recorded pid (and its children) is really gone
if [ -n "$SESSION_PID" ]; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$SESSION_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$SESSION_PID" 2>/dev/null; then
    echo "auditgw (pid $SESSION_PID) still alive; killing it and its children."
    pkill -P "$SESSION_PID" 2>/dev/null || true
    kill "$SESSION_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$SESSION_PID" 2>/dev/null || true
  fi
fi

echo "stop complete. You can close this window."
