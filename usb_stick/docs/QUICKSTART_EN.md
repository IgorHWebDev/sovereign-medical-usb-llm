# Quick Start (English)

Offline medical documentation copilot — runs entirely from this USB stick.
No installation. No admin rights. No internet connection is used or required.

> **Important**: This is an advisory drafting tool with no clinical validation.
> A physician must review and confirm **every** output before it enters the
> medical record. See [LICENSES/DISCLAIMER.md](LICENSES/DISCLAIMER.md).

## Step 1 — Start it

- **Windows**: open the USB drive in Explorer and double-click `START_WINDOWS.bat`.
  - If a blue **"Windows protected your PC"** (SmartScreen) box appears, click
    **More info → Run anyway**. This is expected for unsigned scripts on removable
    media; see [WINDOWS_VALIDATION_CHECKLIST.md](WINDOWS_VALIDATION_CHECKLIST.md).
- **macOS** (Apple Silicon): open the USB drive in Finder and double-click
  `START_MAC.command`.
  - If macOS says the file is from an unidentified developer:
    **right-click (Control-click) the file → Open → Open**.

A black console window opens, loads the model (this can take one to two minutes
on first start), and then your web browser opens automatically at an address
like `http://127.0.0.1:8180/`. That address is *inside this PC only* — nothing
leaves the machine.

## Step 2 — Draft a document

1. In the browser page, pick a document preset on the left:
   - 退院サマリー (Discharge Summary)
   - 手術記録 (Operative Note)
   - 看護記録・SOAP (Nursing Record, SOAP)
   - 診療情報提供書 (Referral Letter)
   - 匿名化支援 (De-identification Assist)
2. Fill in the short form / paste your clinical notes.
3. Press generate and wait for the draft.

Do **not** enter patient names, patient IDs, addresses, or phone numbers —
the presets are designed to work from age/sex plus clinical facts.

## Step 3 — Review, copy out, and stop

1. **Read the whole draft.** Correct every error and everything marked
   `【要確認】` (needs confirmation). You, the physician, are the author.
2. Copy the corrected text into the medical record system by hand.
3. When finished: close the browser tab and run `STOP_WINDOWS.bat` (Windows) or
   `STOP_MAC.command` (macOS), wait for the console window to close, then use
   "Safely Remove Hardware" / drag-to-eject before unplugging the stick.
4. Return the stick and sign it back in on the custody register
   ([CUSTODY_REGISTER_TEMPLATE.md](CUSTODY_REGISTER_TEMPLATE.md)).

## If something goes wrong

- Nothing happens / window closes instantly: try again from a different USB port;
  make sure you copied nothing out of the stick — it must run from the stick root.
- Browser did not open: open it yourself and go to `http://127.0.0.1:8180/`
  (try 8181–8199 if busy).
- Very slow: the host PC has little RAM (< 8 GB) — use a better-equipped PC.
- First use on a new Windows PC: follow
  [WINDOWS_VALIDATION_CHECKLIST.md](WINDOWS_VALIDATION_CHECKLIST.md) once, with IT support present.

Japanese version: [QUICKSTART_JA.md](QUICKSTART_JA.md)
