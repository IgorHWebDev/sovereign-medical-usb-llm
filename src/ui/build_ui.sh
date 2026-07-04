#!/bin/bash
# build_ui.sh — inline src/ui/presets.json into src/ui/index.template.html and
# emit the fully self-contained usb_stick/ui/index.html.
# Writes to a temp name then mv (never deletes under usb_stick/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/src/ui"
OUT_DIR="$ROOT/usb_stick/ui"
OUT="$OUT_DIR/index.html"
TMP="$OUT_DIR/.index.html.build.tmp"

mkdir -p "$OUT_DIR"

python3 - "$SRC/presets.json" "$SRC/index.template.html" "$TMP" <<'PY'
import json, sys, re

presets_path, tpl_path, out_path = sys.argv[1:4]

with open(presets_path, encoding="utf-8") as f:
    data = json.load(f)

# --- validate presets.json (source of truth) --------------------------------
required_ids = {"taiin-summary", "operative-note", "nursing-record",
                "referral-letter", "deid-assist"}
presets = data.get("presets")
assert isinstance(presets, list), "presets.json: 'presets' must be a list"
ids = {p.get("id") for p in presets}
missing = required_ids - ids
assert not missing, f"presets.json missing preset ids: {missing}"
for p in presets:
    for key in ("id", "label_ja", "label_en", "system_prompt",
                "input_fields", "template_mode", "stop"):
        assert key in p, f"preset {p.get('id')} missing key {key}"
    assert p["template_mode"] in ("chat", "raw"), f"bad template_mode in {p['id']}"
    assert isinstance(p["stop"], list), f"stop must be a list in {p['id']}"
    assert isinstance(p["input_fields"], list) and p["input_fields"], \
        f"input_fields must be a non-empty list in {p['id']}"
deid = next(p for p in presets if p["id"] == "deid-assist")
sp = deid["system_prompt"]
assert "recall" in sp and "法的" in sp and ("確認" in sp or "検証" in sp), \
    "deid-assist system_prompt must carry the non-legal-grade recall / human-verify caveat"

with open(tpl_path, encoding="utf-8") as f:
    tpl = f.read()

marker = "/*__PRESETS_JSON__*/null"
assert marker in tpl, "template missing /*__PRESETS_JSON__*/null marker"
blob = json.dumps(data, ensure_ascii=False, indent=2)
# Keep the inline <script> safe: forbid '</script' inside the JSON blob.
blob = blob.replace("</", "<\\/")
out = tpl.replace(marker, blob)

# --- self-containment guard: no external URLs outside 127.0.0.1/localhost ---
for m in re.finditer(r"https?://[^\s\"'<>)]+", out):
    url = m.group(0)
    if "127.0.0.1" not in url and "localhost" not in url:
        raise SystemExit(f"external URL found in generated UI: {url}")
# Block only EXTERNAL resources (http/https or protocol-relative //). Inline
# data: URIs and same-origin relative paths are self-contained and allowed.
for pat in (r"<script[^>]+src=\s*['\"]?(?:https?:)?//",
            r"<link[^>]+href=\s*['\"]?(?:https?:)?//",
            r"@import\s+['\"]?(?:https?:)?//",
            r"url\s*\(\s*['\"]?(?:https?:)?//"):
    if re.search(pat, out, re.I):
        raise SystemExit(f"external resource reference matches /{pat}/ — UI must be self-contained")

with open(out_path, "w", encoding="utf-8") as f:
    f.write(out)
print(f"wrote {out_path} ({len(out.encode('utf-8'))} bytes, {len(presets)} presets inlined)")
PY

mv "$TMP" "$OUT"
echo "built: $OUT"
shasum -a 256 "$OUT"
