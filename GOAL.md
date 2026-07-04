# GOAL

**STATUS: COMPLETE** — ALL milestones m0-m12 verified AND full usb-verify adversarial re-validation passed 2026-07-03T23:33:47Z (finalVerifyPassed=true): full artifact re-hash of every recorded file, live mac end-to-end smoke 12/12 at 60.2 tok/s through auditgw on an exFAT image, live checksum re-verification of all pins, tamper-evidence re-proven. Package: usb_stick/ 3.63 GB, 55-file MANIFEST.sha256 (996c6f32...), RWKV-7 World 2.9B Q4_K_M (1.87 GB) + granite-4.0-h-micro Q4_K_M (1.94 GB), llama.cpp b9867 win-x64 + mac-arm64, auditgw hash-chain gateway, single-file offline UI with 5 JA medical presets, dual no-admin launchers, bilingual docs. Phase 1: datasets pinned (m10), baselines RWKV-7 35% / granite 40% on JMMLU-medical-60 (m11), LoRA/SFT kit + local QLoRA smoke complete (m12).

Fully-offline non-Transformer (RWKV-7/Mamba GGUF Q4, 1.5-3.7B, Japanese-capable) medical documentation copilot USB package: llama.cpp engine for win-x64 + mac-arm64, custom offline web UI with JA medical presets, auditgw Go gateway with tamper-evident hash-chain logging, dual no-admin launchers, bilingual docs. EXTENDED (Phase 1): m10 open JA-medical datasets (license-verified, no raw PHI), m11 baseline eval of both shipped models, m12 LoRA/SFT fine-tuning pipeline with local smoke or validated remote GPU recipe.

## Milestones

| id | title | status |
|----|-------|--------|
| m0 | Research/pin: DECISIONS.json + build/versions.lock | verified |
| m1 | Scaffold: repo + usb_stick/ tree + checks stubs + GOAL.md | verified |
| m2 | Engine binaries: llama.cpp for mac-arm64 (runs) + win-x64 (checksummed) | verified |
| m3 | Models fetched + verified + live engine gate (DISK GATE >= 15 GB free) | verified |
| m4 | auditgw: Go gateway built for both OSes + hash-chain unit test | verified |
| m5 | Custom web UI: single-file offline, JA medical presets, operator capture | verified |
| m6 | Dual launchers: START_MAC.command + START_WINDOWS.bat (+ STOP) | verified |
| m7 | macOS end-to-end smoke test + Japanese bake-off | verified |
| m8 | Bilingual docs + Windows manual checklist + licenses | verified |
| m9 | Final package validation + MANIFEST.sha256 | verified |
| m10 | Datasets: open Japanese medical eval + SFT corpora researched, license-verified, fetched | verified |
| m11 | Baseline eval harness: both shipped GGUFs scored on a JA medical benchmark | verified |
| m12 | Fine-tuning pipeline: LoRA/SFT kit + local smoke run (or validated remote GPU recipe) | verified |
