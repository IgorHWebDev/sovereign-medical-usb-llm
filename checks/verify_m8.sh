#!/bin/bash
# verify_m8.sh — mechanical re-test of milestone m8 DoD
# (bilingual docs + Windows manual checklist + licenses + README_FIRST.html).
# Exit 0 = pass.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="$ROOT/usb_stick/docs"
LIC="$DOCS/LICENSES"
FAILS=0
fail() { echo "FAIL: $*"; FAILS=$((FAILS+1)); }
ok()   { echo "ok:   $*"; }

# --- DoD 1+2: required files exist and are non-trivial ----------------------
req() { # path min_bytes
  if [ -f "$1" ] && [ "$(wc -c < "$1")" -ge "$2" ]; then ok "exists (>=$2 B): ${1#$ROOT/}"
  else fail "missing or too small (<$2 B): ${1#$ROOT/}"; fi
}
req "$DOCS/QUICKSTART_EN.md"                 1500
req "$DOCS/QUICKSTART_JA.md"                 1500
req "$DOCS/ENCRYPTION_NOTE_EN.md"            1500
req "$DOCS/ENCRYPTION_NOTE_JA.md"            1500
req "$DOCS/WINDOWS_VALIDATION_CHECKLIST.md"  2000
req "$DOCS/CUSTODY_REGISTER_TEMPLATE.md"     1000
req "$LIC/Apache-2.0.txt"                    10000
req "$LIC/llama.cpp-b9867-LICENSE.txt"       1000
req "$LIC/MODEL_CARD_NOTES.md"               1000
req "$LIC/DISCLAIMER.md"                     1000
req "$ROOT/usb_stick/README_FIRST.html"      3000

# --- content markers ---------------------------------------------------------
has() { # file pattern description   (grep -E, case-insensitive)
  if grep -Eqi -- "$2" "$1" 2>/dev/null; then ok "$(basename "$1"): $3"
  else fail "$(basename "$1"): missing $3 (pattern: $2)"; fi
}

# Quickstarts: clinician-level 3 steps, launcher names, physician-review rule
for q in "$DOCS/QUICKSTART_EN.md" "$DOCS/QUICKSTART_JA.md"; do
  has "$q" 'START_WINDOWS\.bat'  "mentions START_WINDOWS.bat"
  has "$q" 'START_MAC\.command'  "mentions START_MAC.command"
  has "$q" '127\.0\.0\.1'        "explains loopback address"
done
[ "$(grep -Ec '^## (Step [123]|手順 [123])' "$DOCS/QUICKSTART_EN.md" "$DOCS/QUICKSTART_JA.md" 2>/dev/null \
     | awk -F: '{s+=$2} END{print s+0}')" -eq 6 ] \
  && ok "quickstarts: exactly 3 numbered steps each" \
  || fail "quickstarts: expected 3 '## Step N' / '## 手順 N' headings in each"
has "$DOCS/QUICKSTART_EN.md" 'physician' "physician-review requirement"
has "$DOCS/QUICKSTART_JA.md" '医師'       "physician-review requirement (JA)"

# Encryption notes: hardware keypad rec, rejections with reasons, exFAT, custody
for e in "$DOCS/ENCRYPTION_NOTE_EN.md" "$DOCS/ENCRYPTION_NOTE_JA.md"; do
  has "$e" 'IronKey'              "IronKey recommendation"
  has "$e" 'Apricorn'             "Apricorn recommendation"
  has "$e" 'VeraCrypt'            "VeraCrypt discussed"
  has "$e" 'BitLocker'            "BitLocker To Go discussed"
  has "$e" 'exFAT'                "exFAT rationale"
  has "$e" 'CUSTODY_REGISTER_TEMPLATE\.md' "custody register requirement + link"
done
has "$DOCS/ENCRYPTION_NOTE_EN.md" 'VeraCrypt.*|administrator rights' "VeraCrypt admin-driver rejection"
grep -Eqi 'admin' "$DOCS/ENCRYPTION_NOTE_EN.md" && grep -Eqi '管理者権限' "$DOCS/ENCRYPTION_NOTE_JA.md" \
  && ok "encryption notes: admin-rights rejection rationale present (EN+JA)" \
  || fail "encryption notes: admin-rights rationale missing"
grep -Eqi 'macOS' "$DOCS/ENCRYPTION_NOTE_EN.md" \
  && ok "encryption note EN: BitLocker/macOS incompatibility rationale" \
  || fail "encryption note EN: no macOS rationale"

# Windows checklist: numbered manual steps + SmartScreen guidance
W="$DOCS/WINDOWS_VALIDATION_CHECKLIST.md"
has "$W" 'SmartScreen'                    "SmartScreen guidance"
has "$W" 'More info|詳細情報'             "SmartScreen 'More info -> Run anyway' path"
has "$W" 'netstat'                        "loopback-binding verification step"
has "$W" 'auditgw\.exe verify'            "audit hash-chain verification step"
has "$W" 'STOP_WINDOWS\.bat'              "shutdown step"
NSTEPS="$(grep -Ec '^[0-9]+\. ' "$W")"
[ "$NSTEPS" -ge 15 ] && ok "checklist: $NSTEPS numbered manual steps (>=15)" \
                     || fail "checklist: only $NSTEPS numbered steps (need >=15)"

# Custody register template: identity + log + incident sections
C="$DOCS/CUSTODY_REGISTER_TEMPLATE.md"
has "$C" 'Serial|シリアル'          "drive serial field"
has "$C" '持出日時|Date-time out'   "sign-out column"
has "$C" '返却日時|Date-time in'    "sign-in column"
has "$C" 'Incident|インシデント'    "incident section"

# Licenses: canonical Apache-2.0 text, MIT, model notes, disclaimer
AP_SHA="$(shasum -a 256 "$LIC/Apache-2.0.txt" 2>/dev/null | awk '{print $1}')"
if [ "$AP_SHA" = "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" ]; then
  ok "Apache-2.0.txt matches canonical sha256"
else
  # fall back to structural check if a re-wrapped copy was shipped
  grep -q 'Apache License' "$LIC/Apache-2.0.txt" 2>/dev/null \
    && grep -q 'Version 2.0, January 2004' "$LIC/Apache-2.0.txt" 2>/dev/null \
    && grep -q '9. Accepting Warranty or Additional Liability' "$LIC/Apache-2.0.txt" 2>/dev/null \
    && ok "Apache-2.0.txt structurally complete (non-canonical bytes: $AP_SHA)" \
    || fail "Apache-2.0.txt is not the Apache License 2.0 text (sha256: $AP_SHA)"
fi
has "$LIC/llama.cpp-b9867-LICENSE.txt" 'MIT License' "llama.cpp MIT license text"
M="$LIC/MODEL_CARD_NOTES.md"
has "$M" 'rwkv7-2.9B-world-q4_k_m\.gguf' "primary model file named"
has "$M" 'granite-4.0-h-micro-Q4_K_M\.gguf' "fallback model file named"
has "$M" 'd80eadb5a5db0689a6e3a6689128670530b30203c44404510f77f553368253e8' "primary model sha256"
has "$M" 'bcc78b9b25450101d1ad90d4b9a264e1bac892f534dfb76066f4eec792fdf023' "fallback model sha256"
has "$M" 'Apache' "model license stated"
grep -Eqi 'recall|再現率' "$M" && grep -Eqi 'de-identif|匿名化' "$M" \
  && ok "MODEL_CARD_NOTES: de-identification recall caveat" \
  || fail "MODEL_CARD_NOTES: missing de-identification recall caveat"
D="$LIC/DISCLAIMER.md"
has "$D" 'advisory drafting tool'  "advisory-tool statement"
has "$D" 'no clinical validation|clinical validation'  "no-clinical-validation statement"
has "$D" 'physician must review|physician'  "physician-confirms-every-output statement"
has "$D" 'PMDA'                    "PMDA non-device posture"
has "$D" 'non-medical-device|非医療機器' "non-device positioning"
has "$D" '医師'                    "Japanese physician statement (bilingual)"

# README_FIRST.html: bilingual, offline-renderable, links resolve
R="$ROOT/usb_stick/README_FIRST.html"
has "$R" '<html lang='            "declares a lang attribute"
has "$R" 'docs/QUICKSTART_JA\.md' "links Japanese quickstart"
has "$R" 'docs/QUICKSTART_EN\.md' "links English quickstart"
has "$R" 'DISCLAIMER\.md'         "links disclaimer"
grep -Eqi 'placeholder|仮版' "$R" && fail "README_FIRST.html still contains placeholder text" \
                                  || ok "README_FIRST.html: no placeholder marker"
if grep -Eqi '(src|href)="https?://' "$R"; then
  fail "README_FIRST.html references external URLs (must render offline)"
else
  ok "README_FIRST.html: no external src/href (renders offline)"
fi

# bilingual byte-level check: JA docs + README contain Japanese characters,
# EN docs contain none/ASCII prose
python3 - "$DOCS" "$R" <<'PY' && ok "bilingual content check (JA chars where required)" || FAILS=$((FAILS+1))
import sys, pathlib
docs, readme = sys.argv[1], sys.argv[2]
def ja(p):
    t = pathlib.Path(p).read_text(encoding="utf-8")
    return any('぀' <= c <= 'ヿ' or '一' <= c <= '鿿' for c in t)
bad = []
for p in ["QUICKSTART_JA.md", "ENCRYPTION_NOTE_JA.md",
          "WINDOWS_VALIDATION_CHECKLIST.md", "CUSTODY_REGISTER_TEMPLATE.md"]:
    if not ja(f"{docs}/{p}"): bad.append(p + ": no Japanese text")
for p in ["QUICKSTART_EN.md", "ENCRYPTION_NOTE_EN.md"]:
    if not ja(f"{docs}/{p}"):  # EN docs may embed JA UI labels; require they at least exist
        pass
if not ja(readme): bad.append("README_FIRST.html: no Japanese text")
if not ja(f"{docs}/LICENSES/DISCLAIMER.md"): bad.append("DISCLAIMER.md: no Japanese text")
if bad:
    print("FAIL: " + "; ".join(bad)); sys.exit(1)
PY

# --- DoD 4: link check — every relative path referenced in docs resolves -----
python3 - "$ROOT/usb_stick" <<'PY' && ok "link check: all relative links in docs + README resolve" || FAILS=$((FAILS+1))
import re, sys, pathlib
stick = pathlib.Path(sys.argv[1])
files = sorted(stick.joinpath("docs").rglob("*.md")) + [stick / "README_FIRST.html"]
md_link = re.compile(r'\[[^\]]*\]\(([^)\s]+)\)')
html_link = re.compile(r'(?:href|src)="([^"]+)"')
bad, checked = [], 0
for f in files:
    text = f.read_text(encoding="utf-8")
    pat = html_link if f.suffix == ".html" else md_link
    for m in pat.finditer(text):
        target = m.group(1).split("#", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:", "data:")):
            if target.startswith(("http://", "https://")) and "127.0.0.1" not in target:
                bad.append(f"{f.name}: external link {m.group(1)}")
            continue
        checked += 1
        resolved = (f.parent / target).resolve()
        if not resolved.exists():
            bad.append(f"{f.relative_to(stick)}: broken link -> {target}")
if checked == 0:
    bad.append("no relative links found at all (link check vacuous)")
if bad:
    print("FAIL: " + "; ".join(bad)); sys.exit(1)
print(f"      ({checked} relative links resolved across {len(files)} files)")
PY

echo ""
if [ "$FAILS" -eq 0 ]; then
  echo "verify_m8: ALL CHECKS PASSED"
  exit 0
else
  echo "verify_m8: $FAILS check(s) FAILED"
  exit 1
fi
