#!/bin/bash
# START_MAC.command -- med-usb launcher for macOS (Apple Silicon).
# Double-click to start. No installation, no admin rights required.
# Everything is resolved relative to the stick root; servers bind 127.0.0.1 only.
# auditgw supervises llama-server (--spawn-llm), so this script only prepares
# the environment, picks free ports, starts auditgw and opens the browser.

set -u

# ---------------------------------------------------------------------------
# 0) Resolve our own directory (works from any mount point; relative paths only)
# ---------------------------------------------------------------------------
STICK="$(cd "$(dirname "$0")" && pwd)"
cd "$STICK" || { echo "ERROR: cannot cd to stick root"; exit 1; }

echo "================================================="
echo " med-usb : offline medical documentation copilot"
echo " (stick root = folder containing this launcher)"
echo "================================================="

pause_exit() {
  echo ""
  echo "$1"
  echo "Press Enter to close this window."
  read -r _
  exit "${2:-1}"
}

# ---------------------------------------------------------------------------
# 1) Self-heal Gatekeeper quarantine (best effort, errors ignored, no admin)
# ---------------------------------------------------------------------------
/usr/bin/xattr -dr com.apple.quarantine . 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2) Read stick.config (key=value)
# ---------------------------------------------------------------------------
CONFIG="stick.config"
[ -f "$CONFIG" ] || pause_exit "ERROR: stick.config not found next to this launcher."

cfg() { sed -n "s/^$1=//p" "$CONFIG" | head -n 1; }

DEFAULT_MODEL="$(cfg default_model)"
FALLBACK_MODEL="$(cfg fallback_model)"
CTX="$(cfg ctx)";                  [ -n "$CTX" ] || CTX=8192
THREADS="$(cfg threads)";          [ -n "$THREADS" ] || THREADS=auto
LLM_RANGE="$(cfg llm_port_range)"; [ -n "$LLM_RANGE" ] || LLM_RANGE=8080-8099
UI_RANGE="$(cfg ui_port_range)";   [ -n "$UI_RANGE" ] || UI_RANGE=8180-8199
NO_MMAP="$(cfg no_mmap)"
BUILD_ID="$(cfg build_id)";        [ -n "$BUILD_ID" ] || BUILD_ID="med-usb"

# ---------------------------------------------------------------------------
# 3) RAM check via sysctl hw.memsize (warn below 8 GB, do not block)
# ---------------------------------------------------------------------------
MEM_BYTES="$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null || echo 0)"
MIN_BYTES=$((8 * 1024 * 1024 * 1024))
if [ "${MEM_BYTES:-0}" -lt "$MIN_BYTES" ]; then
  echo "WARNING: this Mac reports less than 8 GB of RAM."
  echo "         The model may run very slowly or fail to load."
fi

if [ "$THREADS" = "auto" ]; then
  THREADS="$(/usr/sbin/sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

# ---------------------------------------------------------------------------
# 4) Pick the model (default, then fallback)
# ---------------------------------------------------------------------------
MODEL=""
if [ -n "$DEFAULT_MODEL" ] && [ -f "models/$DEFAULT_MODEL" ]; then
  MODEL="$DEFAULT_MODEL"
elif [ -n "$FALLBACK_MODEL" ] && [ -f "models/$FALLBACK_MODEL" ]; then
  echo "NOTE: default model not found; using fallback model."
  MODEL="$FALLBACK_MODEL"
else
  echo "Files currently in models/:"
  ls -1 models 2>/dev/null || echo "  (models/ is missing or empty)"
  pause_exit "ERROR: no model file found in models/ (expected: ${DEFAULT_MODEL:-?} or ${FALLBACK_MODEL:-?})."
fi

MODEL_SHA=""
if [ -f "models/$MODEL.sha256" ]; then
  MODEL_SHA="$(awk '{print $1; exit}' "models/$MODEL.sha256")"
fi

# ---------------------------------------------------------------------------
# 5) Free-port scan in the configured ranges (pure bash /dev/tcp probe:
#    a successful connect means the port is already in use)
# ---------------------------------------------------------------------------
port_in_use() {
  ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null
}

first_free_port() {
  local lo hi p
  lo="${1%-*}"; hi="${1#*-}"
  for ((p = lo; p <= hi; p++)); do
    if ! port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

LLM_PORT="$(first_free_port "$LLM_RANGE")" || pause_exit "ERROR: no free port in llm_port_range $LLM_RANGE."
UI_PORT="$(first_free_port "$UI_RANGE")"   || pause_exit "ERROR: no free port in ui_port_range $UI_RANGE."

# ---------------------------------------------------------------------------
# 6) Start auditgw with --spawn-llm (auditgw launches and supervises llama-server)
# ---------------------------------------------------------------------------
AGW="bin/mac-arm64/auditgw"
LLM_BIN="bin/mac-arm64/llama-server"
[ -f "$AGW" ]     || pause_exit "ERROR: $AGW missing."
[ -f "$LLM_BIN" ] || pause_exit "ERROR: $LLM_BIN missing."
chmod +x "$AGW" "$LLM_BIN" 2>/dev/null || true

LLM_ARGS="--model models/$MODEL --host 127.0.0.1 --port $LLM_PORT --ctx-size $CTX --threads $THREADS"
if [ "$NO_MMAP" = "true" ]; then
  LLM_ARGS="$LLM_ARGS --no-mmap"
fi

mkdir -p audit
GWLOG="audit/gateway-mac.log"

echo "starting auditgw (UI http://127.0.0.1:$UI_PORT/ , llm port $LLM_PORT , model $MODEL, $THREADS threads)"
echo "gateway log: $GWLOG"

set -- serve --spawn-llm --llm-bin "$LLM_BIN" --llm-args "$LLM_ARGS" \
  --ui-dir ui --ui-port "$UI_PORT" --llm-port "$LLM_PORT" \
  --audit-dir audit --model-file "$MODEL" --build-id "$BUILD_ID"
if [ -n "$MODEL_SHA" ]; then
  set -- "$@" --model-sha256 "$MODEL_SHA"
fi
"$AGW" "$@" >>"$GWLOG" 2>&1 &
AGW_PID=$!

{
  echo "ui_port=$UI_PORT"
  echo "llm_port=$LLM_PORT"
  echo "pid=$AGW_PID"
  echo "model=$MODEL"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > audit/session-mac.env

# ---------------------------------------------------------------------------
# 7) Session-end audit event + signal handling (kill children on INT/TERM/HUP)
# ---------------------------------------------------------------------------
SESSION_ENDED=0
write_session_end() {
  if [ "$SESSION_ENDED" = "1" ]; then return 0; fi
  SESSION_ENDED=1
  "$AGW" append --file "audit/audit-$(date -u +%Y%m).jsonl" \
    --operator "launcher:mac" \
    --prompt "session-end" \
    --response "session ended $(date -u +%Y-%m-%dT%H:%M:%SZ) ui_port=$UI_PORT llm_port=$LLM_PORT model=$MODEL" \
    --model-file "$MODEL" --build-id "$BUILD_ID" >/dev/null 2>&1 || true
}

cleanup() {
  trap - INT TERM HUP
  echo ""
  echo "stopping med-usb (signal received) ..."
  # graceful first: auditgw stops its supervised llama-server on shutdown
  curl -s -m 3 -X POST "http://127.0.0.1:$UI_PORT/api/shutdown" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$AGW_PID" 2>/dev/null || break
    sleep 1
  done
  if kill -0 "$AGW_PID" 2>/dev/null; then
    # hard fallback: kill auditgw and any children it spawned (llama-server)
    pkill -P "$AGW_PID" 2>/dev/null || true
    kill "$AGW_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$AGW_PID" 2>/dev/null || true
  fi
  write_session_end
  echo "stopped."
  exit 0
}
trap cleanup INT TERM HUP

# ---------------------------------------------------------------------------
# 8) Wait for health, then open the browser
# ---------------------------------------------------------------------------
echo "waiting for the gateway to come up ..."
GW_UP=0
for _ in $(seq 1 60); do
  if curl -s -m 2 "http://127.0.0.1:$UI_PORT/api/status" >/dev/null 2>&1; then
    GW_UP=1
    break
  fi
  kill -0 "$AGW_PID" 2>/dev/null || pause_exit "ERROR: auditgw exited early. See $GWLOG"
  sleep 1
done
[ "$GW_UP" = "1" ] || pause_exit "ERROR: gateway not answering on port $UI_PORT after 60s. See $GWLOG"

echo "gateway is up. waiting for the model to load (large models can take minutes) ..."
LLM_UP=0
for _ in $(seq 1 300); do
  if curl -s -m 2 "http://127.0.0.1:$UI_PORT/api/status" 2>/dev/null | grep -q '"llm_reachable":true'; then
    LLM_UP=1
    break
  fi
  sleep 1
done
if [ "$LLM_UP" = "1" ]; then
  echo "model is ready."
else
  echo "WARNING: model not ready after 5 minutes; opening the UI anyway (it will keep retrying)."
fi

open "http://127.0.0.1:$UI_PORT/" 2>/dev/null || echo "Open http://127.0.0.1:$UI_PORT/ in your browser."

echo ""
echo "med-usb is running:  http://127.0.0.1:$UI_PORT/"
echo "Keep this window open while you work."
echo "To stop: double-click STOP_MAC.command (or press Ctrl+C here)."
echo ""

wait "$AGW_PID" 2>/dev/null
write_session_end
echo "session closed. You can close this window."
