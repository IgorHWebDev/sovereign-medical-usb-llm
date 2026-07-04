#!/bin/bash
# verify_m0.sh — mechanical re-test of m0 DoD (DECISIONS.json + build/versions.lock).
# Exit 0 = pass. Structural checks are mandatory; live checksum re-verification runs
# when the network is reachable and is then also mandatory (mismatch = FAIL).
set -u
ROOT="/Users/osx/Documents/med_l_llm"
FAIL=0
note() { echo "[verify_m0] $1"; }
bad()  { echo "[verify_m0] FAIL: $1"; FAIL=1; }

DEC="$ROOT/DECISIONS.json"
LOCK="$ROOT/build/versions.lock"

# --- DoD 1: DECISIONS.json exists and parses ---
[ -f "$DEC" ] || { bad "DECISIONS.json missing"; exit 1; }
python3 - "$DEC" <<'PY' || { bad "DECISIONS.json is not valid JSON"; exit 1; }
import json,sys; json.load(open(sys.argv[1]))
PY
note "DECISIONS.json parses"

# --- DoD 2,3,4: structural pin checks ---
python3 - "$DEC" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1]))
errs = []
hex64 = re.compile(r'^[0-9a-f]{64}$')

for role in ("primary", "fallback"):
    m = d.get("models", {}).get(role)
    if not m:
        errs.append(f"models.{role} missing"); continue
    for k in ("hfRepo", "ggufFilename", "downloadUrl", "sha256", "sizeBytes", "license", "checksumSource"):
        if not m.get(k):
            errs.append(f"models.{role}.{k} missing/empty")
    if m.get("sha256") and not hex64.match(m["sha256"]):
        errs.append(f"models.{role}.sha256 not 64-hex")
    if not isinstance(m.get("sizeBytes"), int) or m.get("sizeBytes", 0) < 10**9:
        errs.append(f"models.{role}.sizeBytes implausible for a ~2-3B Q4 GGUF")
    if m.get("downloadUrl") and m.get("ggufFilename") and not m["downloadUrl"].endswith(m["ggufFilename"]):
        errs.append(f"models.{role}.downloadUrl does not end with ggufFilename")
    if m.get("checksumSource") and "huggingface.co/api/models" not in m["checksumSource"]:
        errs.append(f"models.{role}.checksumSource is not an HF API URL")

p = d.get("models", {}).get("primary", {})
if "rwkv7" not in p.get("hfRepo", "").lower(): errs.append("primary is not an RWKV-7 repo")
if "q4_k_m" not in p.get("ggufFilename", "").lower(): errs.append("primary GGUF is not Q4_K_M")
f = d.get("models", {}).get("fallback", {})
if f.get("hfRepo") != "ibm-granite/granite-4.0-h-micro-GGUF": errs.append("fallback repo is not ibm-granite/granite-4.0-h-micro-GGUF")
if "q4_k_m" not in f.get("ggufFilename", "").lower(): errs.append("fallback GGUF is not Q4_K_M")

lc = d.get("llamaCpp", {})
tag = lc.get("releaseTag", "")
if not tag: errs.append("llamaCpp.releaseTag missing")
if not lc.get("checksumSource"): errs.append("llamaCpp.checksumSource missing")
assets = lc.get("assets", {})
for plat, frag in (("win-x64", "bin-win-cpu-x64.zip"), ("mac-arm64", "bin-macos-arm64.tar.gz")):
    a = assets.get(plat)
    if not a:
        errs.append(f"llamaCpp.assets.{plat} missing"); continue
    for k in ("filename", "url", "sha256", "sizeBytes"):
        if not a.get(k): errs.append(f"llamaCpp.assets.{plat}.{k} missing/empty")
    if a.get("sha256") and not hex64.match(a["sha256"]): errs.append(f"llamaCpp.assets.{plat}.sha256 not 64-hex")
    if a.get("filename") and (frag not in a["filename"] or tag not in a["filename"]):
        errs.append(f"llamaCpp.assets.{plat}.filename does not match llama-<TAG>-{frag}")
    if a.get("url") and tag not in a["url"]: errs.append(f"llamaCpp.assets.{plat}.url does not contain tag")

rt = d.get("runtime", {})
if rt.get("llamaServerPortRange") != "8080-8099": errs.append("runtime.llamaServerPortRange != 8080-8099")
if rt.get("auditgwUiPortRange") != "8180-8199": errs.append("runtime.auditgwUiPortRange != 8180-8199")
api = rt.get("apiShape", {})
if api.get("primary") != "/v1/chat/completions": errs.append("apiShape.primary != /v1/chat/completions")
if api.get("fallback") != "/completion": errs.append("apiShape.fallback != /completion")

for e in errs: print("STRUCT:", e)
sys.exit(1 if errs else 0)
PY
[ $? -eq 0 ] || bad "DECISIONS.json structural checks failed"
[ $FAIL -eq 0 ] && note "DECISIONS.json structure OK"

# --- DoD 5: versions.lock exists and mirrors pins ---
[ -f "$LOCK" ] || { bad "build/versions.lock missing"; exit 1; }
python3 - "$DEC" "$LOCK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
lock = {}
for line in open(sys.argv[2]):
    line = line.strip()
    if not line or line.startswith("#"): continue
    if "=" in line:
        k, v = line.split("=", 1)
        lock[k.strip()] = v.strip()
pairs = []
for role in ("primary", "fallback"):
    m = d["models"][role]
    pairs += [
        (f"model.{role}.hf_repo", m["hfRepo"]),
        (f"model.{role}.gguf_filename", m["ggufFilename"]),
        (f"model.{role}.url", m["downloadUrl"]),
        (f"model.{role}.sha256", m["sha256"]),
        (f"model.{role}.size_bytes", str(m["sizeBytes"])),
        (f"model.{role}.license", m["license"]),
        (f"model.{role}.checksum_source", m["checksumSource"]),
    ]
lc = d["llamaCpp"]
pairs.append(("llamacpp.tag", lc["releaseTag"]))
for plat, key in (("win-x64", "win_x64"), ("mac-arm64", "mac_arm64")):
    a = lc["assets"][plat]
    pairs += [
        (f"llamacpp.{key}.url", a["url"]),
        (f"llamacpp.{key}.sha256", a["sha256"]),
        (f"llamacpp.{key}.size_bytes", str(a["sizeBytes"])),
    ]
rt = d["runtime"]
pairs += [
    ("runtime.llm_port_range", rt["llamaServerPortRange"]),
    ("runtime.ui_port_range", rt["auditgwUiPortRange"]),
    ("runtime.api_primary", rt["apiShape"]["primary"]),
    ("runtime.api_fallback", rt["apiShape"]["fallback"]),
]
errs = [f"lock mismatch/missing: {k} (want {v!r}, got {lock.get(k)!r})"
        for k, v in pairs if lock.get(k) != v]
for e in errs: print("LOCK:", e)
sys.exit(1 if errs else 0)
PY
[ $? -eq 0 ] || bad "versions.lock does not mirror DECISIONS.json"
[ $FAIL -eq 0 ] && note "versions.lock mirrors DECISIONS.json"

# --- Live re-verification (mandatory when network reachable) ---
if curl -s --max-time 10 -o /dev/null "https://huggingface.co"; then
    note "network reachable — re-verifying checksums live"
    python3 - "$DEC" <<'PY'
import json, sys, urllib.request
d = json.load(open(sys.argv[1]))
errs = []
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": "med-usb-verify-m0"})
    return json.load(urllib.request.urlopen(req, timeout=30))
for role in ("primary", "fallback"):
    m = d["models"][role]
    try:
        api = get("https://huggingface.co/api/models/%s?blobs=true" % m["hfRepo"])
        sib = {s["rfilename"]: s for s in api.get("siblings", [])}
        s = sib.get(m["ggufFilename"])
        if not s:
            errs.append(f"{role}: file {m['ggufFilename']} not in repo {m['hfRepo']}")
        else:
            lfs = s.get("lfs") or {}
            if lfs.get("sha256") != m["sha256"]: errs.append(f"{role}: live sha256 {lfs.get('sha256')} != pinned {m['sha256']}")
            if s.get("size") != m["sizeBytes"]: errs.append(f"{role}: live size {s.get('size')} != pinned {m['sizeBytes']}")
    except Exception as e:
        errs.append(f"{role}: HF API error {e}")
try:
    lc = d["llamaCpp"]
    rel = get("https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/%s" % lc["releaseTag"])
    by_name = {a["name"]: a for a in rel.get("assets", [])}
    for plat in ("win-x64", "mac-arm64"):
        a = lc["assets"][plat]
        ga = by_name.get(a["filename"])
        if not ga:
            errs.append(f"llamacpp {plat}: asset {a['filename']} not in release"); continue
        dig = (ga.get("digest") or "").replace("sha256:", "")
        if dig and dig != a["sha256"]: errs.append(f"llamacpp {plat}: live digest {dig} != pinned {a['sha256']}")
        if ga.get("size") != a["sizeBytes"]: errs.append(f"llamacpp {plat}: live size {ga.get('size')} != pinned {a['sizeBytes']}")
except Exception as e:
    errs.append(f"llamacpp: GitHub API error {e}")
for e in errs: print("LIVE:", e)
sys.exit(1 if errs else 0)
PY
    [ $? -eq 0 ] || bad "live checksum re-verification failed"
    [ $FAIL -eq 0 ] && note "live checksums match pins"
else
    note "network unreachable — skipping live re-verification (structural checks still enforced)"
fi

if [ $FAIL -eq 0 ]; then
    note "PASS"
    exit 0
else
    note "FAIL"
    exit 1
fi
