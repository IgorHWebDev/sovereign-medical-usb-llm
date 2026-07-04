#!/bin/bash
# verify_m2.sh — m2: Engine binaries: llama.cpp mac-arm64 (runs) + win-x64 (checksummed)
# Exit 0 = all DoD items hold. Any failure => non-zero exit with a reason.
set -u
ROOT="/Users/osx/Documents/med_l_llm"
DEC="$ROOT/DECISIONS.json"
MAC="$ROOT/usb_stick/bin/mac-arm64"
WIN="$ROOT/usb_stick/bin/win-x64"
DL="$ROOT/downloads"
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; FAIL=1; }
ok()  { say "ok:   $*"; }

[ -f "$DEC" ] || { say "FAIL: DECISIONS.json missing"; exit 1; }

# --- read pins from DECISIONS.json ---
pin() { python3 -c "import json,sys; d=json.load(open('$DEC')); print(d['llamaCpp']['assets']['$1']['$2'])"; }
WIN_SHA=$(pin win-x64 sha256)     || { say "FAIL: cannot read win pin"; exit 1; }
WIN_FN=$(pin win-x64 filename)
WIN_SZ=$(pin win-x64 sizeBytes)
MAC_SHA=$(pin mac-arm64 sha256)
MAC_FN=$(pin mac-arm64 filename)
MAC_SZ=$(pin mac-arm64 sizeBytes)
TAG=$(python3 -c "import json; print(json.load(open('$DEC'))['llamaCpp']['releaseTag'])")

# --- DoD 3: archives staged in downloads/ and matching pinned sha256+size ---
for spec in "$MAC_FN:$MAC_SHA:$MAC_SZ" "$WIN_FN:$WIN_SHA:$WIN_SZ"; do
  f="${spec%%:*}"; rest="${spec#*:}"; want_sha="${rest%%:*}"; want_sz="${rest#*:}"
  if [ ! -f "$DL/$f" ]; then bad "downloads/$f missing"; continue; fi
  sz=$(stat -f%z "$DL/$f" 2>/dev/null || stat -c%s "$DL/$f")
  [ "$sz" = "$want_sz" ] || bad "downloads/$f size $sz != pinned $want_sz"
  got=$(shasum -a 256 "$DL/$f" | awk '{print $1}')
  if [ "$got" = "$want_sha" ]; then ok "downloads/$f sha256 matches pin"; else bad "downloads/$f sha256 $got != pinned $want_sha"; fi
done

# --- DoD 1: mac-arm64 llama-server exists, executable, runs, dylibs alongside ---
if [ -x "$MAC/llama-server" ]; then
  ok "mac llama-server exists and is executable"
else
  bad "mac llama-server missing or not executable"
fi
for d in libllama-server-impl.dylib libllama-common.0.dylib libllama.0.dylib libmtmd.0.dylib \
         libggml.0.dylib libggml-base.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib \
         libggml-metal.0.dylib libggml-rpc.0.dylib; do
  if [ -f "$MAC/$d" ]; then
    # must be a real file, not a symlink (exFAT sticks cannot hold symlinks)
    [ -L "$MAC/$d" ] && bad "mac $d is a symlink (must be a real file for exFAT)"
  else
    bad "mac dylib $d missing"
  fi
done
if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ] && [ -x "$MAC/llama-server" ]; then
  VOUT=$(cd "$MAC" && ./llama-server --version 2>&1); rc=$?
  if [ $rc -eq 0 ]; then ok "llama-server --version exit 0 ($(printf '%s' "$VOUT" | head -1))"; else bad "llama-server --version exit $rc: $VOUT"; fi
  # --version prints the numeric build (e.g. "version: 9867 (...)"); pin tag is "b9867"
  printf '%s' "$VOUT" | grep -q "version: ${TAG#b}" || bad "version output does not mention pinned build ${TAG#b} (tag $TAG)"
else
  say "note: not on mac-arm64 host; skipping run test"
fi

# --- DoD 2: win-x64 server exe + required DLLs alongside ---
[ -f "$WIN/llama-server.exe" ] && ok "win llama-server.exe present" || bad "win llama-server.exe missing"
for d in llama-server-impl.dll llama.dll llama-common.dll mtmd.dll ggml.dll ggml-base.dll libomp140.x86_64.dll; do
  [ -f "$WIN/$d" ] || bad "win DLL $d missing"
done
NCPU=$(ls "$WIN"/ggml-cpu-*.dll 2>/dev/null | wc -l | tr -d ' ')
if [ "$NCPU" -ge 1 ]; then ok "win ggml-cpu backend DLLs present ($NCPU)"; else bad "no ggml-cpu-*.dll in win-x64"; fi

# --- DoD 3 (second half): only server binaries copied, not the whole toolset ---
for stray in "$MAC/llama-cli" "$MAC/llama-bench" "$MAC/llama-quantize" "$MAC/ggml-rpc-server" \
             "$WIN/llama-cli.exe" "$WIN/llama-bench.exe" "$WIN/llama-quantize.exe" "$WIN/ggml-rpc-server.exe"; do
  [ -e "$stray" ] && bad "extraneous tool shipped: $stray"
done
ok "no extraneous toolset binaries in usb_stick/bin"

if [ "$FAIL" -eq 0 ]; then say "verify_m2: PASS"; exit 0; else say "verify_m2: FAIL"; exit 1; fi
