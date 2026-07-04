#!/bin/bash
# patch_mac_paths.sh — scrub absolute CI build paths from the mac-arm64
# llama.cpp binaries on the stick.
#
# WHY: the official llama.cpp macos-arm64 release binaries embed GitHub
# Actions source paths ("/Users/runner/work/llama.cpp/llama.cpp/...") in
# assert/debug strings. The hospital packaging rule (and m9 DoD) requires
# grep -r "/Users/" usb_stick/ to return nothing. Load commands are already
# relative (@rpath/@loader_path); only inert string constants are affected.
#
# WHAT: byte-for-byte replace "/Users/" -> "/build/" (same length, offsets
# unchanged), write to a temp name, mv over, then re-sign ad-hoc
# (codesign -s - -f) because arm64 macOS requires a valid signature.
# Idempotent: files without the string are left untouched.
#
# Run after any re-extraction of the mac-arm64 engine archive (m2 rebuild),
# BEFORE checks/final_validate.sh.
set -eu
ROOT="/Users/osx/Documents/med_l_llm"
MAC="$ROOT/usb_stick/bin/mac-arm64"
cd "$MAC"

PATCHED=0
for f in *.dylib llama-server; do
  [ -f "$f" ] || continue
  n="$(python3 - "$f" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
data = p.read_bytes()
old, new = b"/Users/", b"/build/"
n = data.count(old)
if n:
    tmp = pathlib.Path(sys.argv[1] + ".patched.tmp")
    tmp.write_bytes(data.replace(old, new))
    tmp.chmod(0o755)
    tmp.rename(p)
print(n)
PY
)"
  if [ "$n" -gt 0 ]; then
    codesign -s - -f "$f" >/dev/null 2>&1
    echo "[patch_mac_paths] $f: scrubbed $n occurrence(s), re-signed ad-hoc"
    PATCHED=$((PATCHED + 1))
  fi
done
echo "[patch_mac_paths] done: $PATCHED file(s) patched"

# Sanity: engine must still run.
if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
  ./llama-server --version >/dev/null 2>&1 || {
    echo "[patch_mac_paths] FAIL: llama-server no longer runs after patch" >&2
    exit 1
  }
  echo "[patch_mac_paths] llama-server --version OK"
fi
# Sanity: no /Users/ left in this directory.
if /usr/bin/grep -rl "/Users/" . >/dev/null 2>&1; then
  echo "[patch_mac_paths] FAIL: /Users/ still present in bin/mac-arm64" >&2
  exit 1
fi
echo "[patch_mac_paths] no /Users/ strings remain in bin/mac-arm64"
