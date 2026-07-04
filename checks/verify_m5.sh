#!/bin/bash
# verify_m5.sh — mechanical re-test of milestone m5 DoD (custom offline web UI).
# Exit 0 = pass. Any failed assertion prints FAIL and exits 1.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
ok()   { echo "ok:   $*"; }

PRESETS="$ROOT/src/ui/presets.json"
INDEX="$ROOT/usb_stick/ui/index.html"
BUILD="$ROOT/src/ui/build_ui.sh"

# --- DoD 1: src/ui/presets.json is the source of truth ----------------------
if [ ! -s "$PRESETS" ]; then
  fail "src/ui/presets.json missing or empty"
else
  if python3 - "$PRESETS" <<'PY'
import json, sys, re
data = json.load(open(sys.argv[1], encoding="utf-8"))
presets = data.get("presets")
assert isinstance(presets, list), "'presets' must be a list"
byid = {p.get("id"): p for p in presets}
required = ["taiin-summary", "operative-note", "nursing-record",
            "referral-letter", "deid-assist"]
for rid in required:
    assert rid in byid, f"missing preset id: {rid}"
jp = re.compile(r"[぀-ヿ一-鿿]")
for p in presets:
    pid = p.get("id")
    for key in ("id", "label_ja", "label_en", "system_prompt",
                "input_fields", "template_mode", "stop"):
        assert key in p, f"{pid}: missing key '{key}'"
    assert p["template_mode"] in ("chat", "raw"), f"{pid}: bad template_mode"
    assert isinstance(p["stop"], list), f"{pid}: stop must be a list"
    assert isinstance(p["input_fields"], list) and p["input_fields"], \
        f"{pid}: input_fields must be a non-empty list"
    for f in p["input_fields"]:
        for fk in ("id", "label_ja", "label_en", "type"):
            assert fk in f, f"{pid}: input_field missing '{fk}'"
    assert jp.search(p["label_ja"]), f"{pid}: label_ja not Japanese"
    sp = p["system_prompt"]
    assert jp.search(sp), f"{pid}: system_prompt not Japanese"
    # few-shot skeleton scaffolding: output-format skeleton + worked example
    assert "出力形式" in sp, f"{pid}: system_prompt lacks output-format skeleton (出力形式)"
    assert "例" in sp and "入力:" in sp and "出力:" in sp, \
        f"{pid}: system_prompt lacks few-shot example (例/入力:/出力:)"
# de-id caveat: recall not legal-grade + human must verify (JA and EN)
sp = byid["deid-assist"]["system_prompt"]
assert "recall" in sp, "deid: no 'recall' mention"
assert "法的" in sp, "deid: no legal-grade caveat (法的)"
assert ("確認" in sp or "検証" in sp), "deid: no human-verify wording"
assert re.search(r"human", sp, re.I), "deid: no English human-verify caveat"
print("presets.json structure OK:", ", ".join(byid))
PY
  then ok "presets.json: 5 presets, required keys, JA few-shot scaffolding, de-id caveat"
  else fail "presets.json structural validation failed"; fi
fi

# --- DoD 2: usb_stick/ui/index.html self-contained with required features ---
if [ ! -s "$INDEX" ]; then
  fail "usb_stick/ui/index.html missing or empty"
else
  # no external resource loading constructs
  grep -qiE '<script[^>]+src=' "$INDEX" && fail "index.html: external <script src=>"
  grep -qiE '<link[^>]+href='  "$INDEX" && fail "index.html: external <link href=>"
  grep -qiE '@import'          "$INDEX" && fail "index.html: CSS @import"
  grep -qiE "url\(['\"]?https?:" "$INDEX" && fail "index.html: css url(http...)"
  grep -qE  '<style'  "$INDEX" || fail "index.html: no inline <style>"
  grep -qE  '<script' "$INDEX" || fail "index.html: no inline <script>"

  # operator capture: login fields -> sessionStorage -> X-Operator-Id header
  grep -q 'sessionStorage'  "$INDEX" || fail "index.html: no sessionStorage operator persistence"
  grep -q 'X-Operator-Id'   "$INDEX" || fail "index.html: no X-Operator-Id header"
  grep -q 'op-name'         "$INDEX" || fail "index.html: no operator name field"
  grep -q 'op-id'           "$INDEX" || fail "index.html: no staff id field"
  grep -q 'op-role'         "$INDEX" || fail "index.html: no role field"
  grep -q 'operatorHeaders' "$INDEX" || fail "index.html: no per-request operator header helper"

  # preset picker JA-first + EN toggle
  grep -q 'label_ja'    "$INDEX" || fail "index.html: no JA-first labels"
  grep -q 'lang-toggle' "$INDEX" || fail "index.html: no EN toggle"

  # streaming chat + model selector + tok/s from llama-server timings
  grep -q '/v1/chat/completions' "$INDEX" || fail "index.html: no /v1/chat/completions endpoint"
  grep -q '"/completion"'        "$INDEX" || fail "index.html: no /completion raw fallback endpoint"
  grep -qE '"?stream"?[[:space:]]*:[[:space:]]*true' "$INDEX" || fail "index.html: no streaming request"
  grep -q 'getReader'                "$INDEX" || fail "index.html: no stream reader"
  grep -q 'model-select'             "$INDEX" || fail "index.html: no model selector"
  grep -q 'predicted_per_second'     "$INDEX" || fail "index.html: tok/s not read from llama-server timings"
  grep -q 'tok/s'                    "$INDEX" || fail "index.html: no tok/s display"

  # audit/offline status banner fed by /api/status
  grep -q '/api/status'    "$INDEX" || fail "index.html: no /api/status feed"
  grep -q 'status-banner'  "$INDEX" || fail "index.html: no status banner element"

  # presets inlined by build_ui.sh and identical to the source of truth
  if python3 - "$PRESETS" "$INDEX" <<'PY'
import json, re, sys
src = json.load(open(sys.argv[1], encoding="utf-8"))
html = open(sys.argv[2], encoding="utf-8").read()
m = re.search(r"const PRESET_DATA = (\{.*?\});\n", html, re.S)
assert m, "PRESET_DATA blob not found in index.html"
inlined = json.loads(m.group(1).replace("<\\/", "</"))
assert inlined == src, "inlined PRESET_DATA differs from src/ui/presets.json"
print("inlined presets identical to source of truth (%d presets)" % len(src["presets"]))
PY
  then ok "index.html: self-contained, operator capture, presets inlined & in sync"
  else fail "index.html: inlined presets missing or out of sync with presets.json"; fi
fi

# build script must exist and be executable (it is the inliner of record)
if [ -x "$BUILD" ]; then ok "src/ui/build_ui.sh executable"; else fail "src/ui/build_ui.sh missing or not executable"; fi

# --- DoD 3: zero external http(s) references across usb_stick/ui ------------
HITS="$(grep -rEo 'https?://[^"'"'"'[:space:]<>)]*' "$ROOT/usb_stick/ui" 2>/dev/null | grep -vE '127\.0\.0\.1|localhost' || true)"
if [ -n "$HITS" ]; then
  fail "external URL(s) in usb_stick/ui:"; echo "$HITS"
else
  ok "no https?:// hits in usb_stick/ui outside 127.0.0.1/localhost"
fi

# --- DoD 4: this script exists and is executable -----------------------------
if [ -x "$ROOT/checks/verify_m5.sh" ]; then
  ok "checks/verify_m5.sh executable"
else
  fail "checks/verify_m5.sh not executable"
fi

# ----------------------------------------------------------------------------
if [ "$FAILS" -eq 0 ]; then
  echo "verify_m5: PASS"
  exit 0
else
  echo "verify_m5: $FAILS failure(s)"
  exit 1
fi
