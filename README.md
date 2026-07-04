# Sovereign Disk-on-Key Medical LLM

A fully-offline medical documentation copilot that runs from a USB stick on
existing hospital PCs — **no installation, no admin rights, and no patient data
ever leaves the machine.** Built for the "Sovereign Hospital AI" engagement
(Osaka University Hospital, T2 disk-on-key tier).

> **Status:** working and verified end-to-end on **macOS (Apple Silicon)**.
> The **Windows** binaries are packaged but not yet hardware-tested — see
> [Known issues](#known-issues).

---

## What it is

- A **non-Transformer** small LLM (RWKV-7 / Mamba-hybrid, GGUF Q4, ~3B) served
  locally by **llama.cpp**, chosen for O(1)/O(N) memory so it stays interactive
  on CPU-only office PCs.
- A **custom offline web UI** (single self-contained HTML file) with Japanese
  medical documentation presets: 退院サマリ (discharge summary), 手術記録
  (op-note), 看護記録 (nursing SOAP), 紹介状 (referral), 匿名化支援 (de-id assist).
  JA/EN draft-language switch.
- **`auditgw`** — a tiny stdlib-only Go gateway that serves the UI, reverse-proxies
  to llama-server, and writes a **tamper-evident hash-chained audit log** of every
  inference (operator ID + prompt/response hashes). This is the compliance
  cornerstone of the design.
- Dual **no-admin launchers** (`START_MAC.command`, `START_WINDOWS.bat`).
- It is an **advisory drafting tool** — a clinician reviews and signs every output
  (deliberately outside the PMDA software-as-a-medical-device envelope).

## Repository layout

```
src/auditgw/        Go gateway: reverse proxy + hash-chain audit log + offline guard
src/ui/             UI source: index.template.html + presets.json + build_ui.sh
src/launchers/      START/STOP for macOS (.command) and Windows (.bat)
build/              fetch + assemble scripts (bash + curl + shasum); versions.lock
checks/             one machine-checkable verify script per milestone
tests/              macOS smoke test, JA bake-off, eval harness, sample prompts
training/           LoRA/SFT fine-tuning kit (scripts only; weights are gitignored)
.claude/workflows/  usb-build.js / usb-verify.js — the autonomous build orchestration
usb_stick/          the shippable package (bin/ + models/ are gitignored — rebuild them)
DECISIONS.json      pinned models + engine: exact URLs, sha256s, sizes, licenses
DATASETS.json       pinned open Japanese-medical datasets (eval + SFT)
STATE.json GOAL.md ledger.ndjson   build state / milestone table / event log
TESTING_FINDINGS.md live-test results and every fix applied
```

**Not in git** (too large; regenerated from the pinned recipe): the GGUF models,
llama.cpp/auditgw binaries, downloaded datasets, and fine-tuning weights. See
`.gitignore`.

## Build it (macOS Apple Silicon)

Prereqs: `bash`, `curl`, `shasum`, `unzip`/`tar`, and **Go** (`brew install go`,
build-time only). ~9 GB free disk for models + cache.

```bash
# 1. Fetch pinned llama.cpp release binaries (both OSes) per DECISIONS.json
bash build/10_fetch_llamacpp.sh
# 2. Fetch pinned GGUF models per DECISIONS.json (verifies sha256)
bash build/20_fetch_models.sh
# 3. Cross-compile the auditgw gateway (darwin/arm64 + windows/amd64)
bash build/30_build_auditgw.sh
# 4. Build the UI (inlines presets into a single offline HTML)
bash src/ui/build_ui.sh
# 5. Assemble usb_stick/ + MANIFEST.sha256
bash build/40_assemble_stick.sh
```

(Exact script names may differ — check `build/`. The whole thing can also be
driven autonomously; see [Autonomous build](#autonomous-build-optional).)

## Run it

Copy the contents of `usb_stick/` to a drive (or run in place), then:

- **macOS (Apple Silicon):** double-click `START_MAC.command`
- **Windows x64:** double-click `START_WINDOWS.bat`

The launcher loads the model (first load from USB can take a minute+), then opens
your browser to `http://127.0.0.1:8180/`. Log in with any name/ID/role, pick a
preset, fill the fields, **Generate**. Stop with `STOP_MAC.command` / `STOP_WINDOWS.bat`.

Everything binds `127.0.0.1` only. Verify the audit chain any time:

```bash
usb_stick/bin/mac-arm64/auditgw verify usb_stick/audit/audit-YYYYMM.jsonl
```

## Test

```bash
bash tests/smoke_macos.sh      # end-to-end from an exFAT image: launch, JA prompt, tok/s, audit tamper test
bash tests/bakeoff_ja.sh       # 5 presets x both models -> pick default_model
python3 tests/eval_ja_med.py   # baseline accuracy on the pinned JA-medical benchmark
```

## Autonomous build (optional)

The whole package is built by an agent loop: `.claude/workflows/usb-build.js`
advances a milestone DAG in `STATE.json` (Select → Build → adversarial Verify →
Record), and `usb-verify.js` is the final full-revalidation gate. `GOAL.md` mirrors
the milestone table; `ledger.ndjson` logs every build/verify/decision event.

## Fine-tuning (the "make it good" phase)

The shipped models are **general-purpose, not medically trained** — baselines are
in `TESTING_FINDINGS.md` / `evals/`. `training/` holds a working LoRA/SFT kit
(local QLoRA smoke proven; remote-GPU recipe documented). The real path per the
proposal: acquire a de-identified gold set through the hospital's governance
committee → SFT off-site on that data only → re-quantize to GGUF → re-pin in
DECISIONS.json → re-run the bake-off and validation before shipping a tuned model.

## Known issues

- **Windows not hardware-tested.** Binaries are packaged and pass structural checks,
  but no real Windows run has confirmed `llama-server.exe` starts. If it shows
  "model loading" forever, check the minimized *med-usb auditgw* window, or run
  `bin\win-x64\llama-server.exe --version` in Command Prompt to isolate the binary.
- **Model tier is small (~3B) and untuned** — treat output as a *draft*, always
  clinician-verified. De-identification recall is **not** legal-grade.
- The demo stick is **plain exFAT (unencrypted)**. Production requires a
  hardware-keypad-encrypted drive — see `usb_stick/docs/ENCRYPTION_NOTE_EN.md`.

## License / data

Models and datasets are Apache-2.0 / permissive and pinned with sources in
`DECISIONS.json` and `DATASETS.json`. No patient data is in this repo; all testing
used synthetic examples.
