# Live Testing Findings — MEDLLM stick on macOS (2026-07-04)

First real end-to-end test of the deployed USB stick (`MEDLLM`, exFAT) on this Mac.
Booted from the stick via `START_MAC.command`, model loaded (~64s from USB, no-mmap),
Japanese and English discharge-summary drafts generated, audit chain verified intact.

## What worked
- Boot from USB with no install/admin; auditgw `--spawn-llm` supervised llama-server.
- Granite-4.0-h-micro generated a coherent Japanese 退院サマリ draft and, when the
  system prompt asked for English, a coherent English draft (~58 tok/s).
- Tamper-evident audit chain: every inference logged with operator ID + prompt/response
  hashes; `auditgw verify` = "chain intact" throughout (ended at 6 entries).
- Offline guard active; servers bound 127.0.0.1 only.

## STATUS 2026-07-04: both fixed & verified live on the stick
- Bug 1 FIXED: auditgw `/api/status` now emits `audit_ok` + `audit_entries`
  (`Chain.VerifySelf()`, lock-safe). Live: `audit_ok:true`, chain intact. Banner
  now reads 正常 / OK. Also fixed the model-name banner (`j.model_file`).
- Bug 2 FIXED (with one residual): added a Draft-language JA/EN selector; the draft
  body now comes out in the chosen language. **Residual**: preset section *headings*
  stay Japanese (they're baked into each preset's few-shot skeleton) — full-English
  headings would need the 5 preset system_prompts localized too.
- Rebuilt: `usb_stick/bin/{mac-arm64,win-x64}/auditgw*`, `usb_stick/ui/index.html`;
  deployed to the `MEDLLM` stick. Repo manifest regenerated (56 files); stick
  manifest regen skipped (macOS `.Spotlight-V100` on exFAT blocks `find` — cosmetic,
  not a runtime issue; the loop's m9 handles clean manifests on a fresh build).

---

## Bug 1 — Audit banner falsely shows "FAILURE" (compliance-visible, must fix)
- Symptom: UI banner always shows 「監査ログ: 異常 — 管理者に連絡してください」 /
  "Audit log: FAILURE — contact the administrator", even though the chain is intact.
- Root cause: field-name mismatch between auditgw and the UI.
  - `ui/index.html` ~line 762:
    `const auditOk = !!(j.audit_ok || (j.audit && (j.audit.chain_ok || j.audit.ok)));`
  - auditgw `/api/status` actually returns: `ok:true`, `audit_last_seq:<n>`,
    `audit_file:"..."` — no `audit_ok` and no nested `audit` object → `auditOk` always false.
- Why it slipped through: m4 unit test + m5 grep test + m7 API smoke never rendered the
  page and read the banner; they hit the API directly.
- Fix options: (a) UI reads the real fields (`ok` + presence of `audit_file`/`audit_last_seq`),
  or preferably (b) auditgw runs a real chain verify and emits `audit_ok` + `audit_entries`
  in `/api/status`, and the UI reads those. Then tighten m7 to assert the rendered banner.

## Bug 2 — Japanese-only output (by design, but no user control)
- Symptom: drafts come out only in Japanese; the top `EN` toggle only switches UI labels,
  not the model's drafting language.
- Root cause: intended — preset system prompts in `src/ui/presets.json` instruct Japanese
  clinical output. The model IS multilingual (verified: produces good English when the
  system prompt asks for English).
- Requested enhancement: add an output-language switch (JA/EN) that swaps/augments the
  preset system prompt so drafts come out in the chosen language. Small edit to
  `presets.json` + the UI language control.

## Suggested next-session work (loop milestones)
- m13: fix Bug 1 in `src/auditgw` + `src/ui`, add a rendered-banner assertion to m7, re-verify, redeploy.
- m14: add JA/EN output-language control (Bug 2), re-verify, redeploy.
Redeploy = rebuild usb_stick/, regenerate MANIFEST.sha256, re-copy to the stick.

## Deployment note
Stick is plain exFAT (unencrypted) — fine for testing; production needs the
hardware-keypad-encrypted drive per `usb_stick/docs/ENCRYPTION_NOTE_EN.md`.
