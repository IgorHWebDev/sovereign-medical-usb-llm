export const meta = {
  name: 'grossing-build',
  description: 'One iteration of the autonomous Sovereign Grossing Voice build: bootstrap STATE, pick eligible milestones, fan out builders, adversarially verify, record. Builds an offline JA/EN speech-to-text + structuring pipeline for pathology grossing in a NEW separate repo.',
  whenToUse: 'Invoked by the /loop driver to advance the grossing voice-to-text build in /Users/osx/Documents/sovereign-grossing-voice until all non-blocked milestones verify.',
  phases: [
    { title: 'Select', detail: 'bootstrap STATE.json if missing; compute eligible milestones from the DAG; re-evaluate blocked unblockHints; early-exit if complete/stalled' },
    { title: 'Build', detail: 'parallel builder agents (cap 3; max 1 network-heavy) for eligible milestones' },
    { title: 'Verify', detail: 'independent adversarial verifier per built milestone re-runs every DoD check, read-only' },
    { title: 'Record', detail: 'single serial agent applies transitions to STATE.json + ledger + GOAL.md; returns progress report' },
  ],
}

const ROOT = '/Users/osx/Documents/sovereign-grossing-voice'
const CORE = '/Users/osx/Documents/med_l_llm'   // shared offline core (becomes the git submodule source)
const STATE = ROOT + '/STATE.json'
const LEDGER = ROOT + '/ledger.ndjson'
const GH_ACCOUNT = 'caesarniseko-coder'
const FORCE_MILESTONE = (args && args.milestone) || null

const INITIAL_STATE = {
  goal: 'Offline, bilingual (JA/EN) speech-to-text + structuring pipeline for pathology GROSSING: whisper.cpp ASR (push-to-talk + Silero VAD so silence is never transcribed) → ~3B LLM structuring (transcript → CAP/ICCR synoptic fields with GBNF grammar, unfilled → VERIFY) → secretary-verified via a transcript-beside-draft UI, auditgw hash-chain logged, accession/barcode-bound, fully offline. Advisory + human-confirmed (non-device). Reuses the sovereign-medical-usb-llm offline core as a git submodule.',
  goalStatus: 'building',
  finalVerifyPassed: false,
  runpodConnectivity: false,   // set true when the user provides RunPod endpoint+key → unblocks g10
  updatedAt: null,
  loopIteration: 0,
  milestones: [
    {
      id: 'g0', title: 'Scaffold: repo + core/ submodule + GitHub repo',
      status: 'pending', dependsOn: [], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'Directory ' + ROOT + ' exists and is a git repo (git init, branch main)',
        'Subdirs exist: src/{asr,capture,structuring,schema,ui,gateway}, data/{synth,templates,gold}, training/{asr_lora,llm_sft}, checks, tests, .claude/workflows',
        'core/ is a git submodule pointing at the sovereign-medical-usb-llm repo (git submodule add https://github.com/' + GH_ACCOUNT + '/sovereign-medical-usb-llm.git core) OR, if the network add fails, a documented placeholder with unblockHint; the submodule reuse target is ' + CORE,
        'GOAL.md (goal + milestone table), README.md (project overview, provenance to core), and .gitignore (exclude models/binaries/venv/audio/*.ggml/*.gguf/*.bin) exist',
        'A NEW private GitHub repo sovereign-grossing-voice is created under ' + GH_ACCOUNT + ' and the initial commit is pushed (gh repo create ... --private --source=. --push). If gh/network fails, mark blocked with the exact command as unblockHint',
        'checks/verify_g0.sh exists and exits 0 (dir + git + submodule presence checks)',
      ],
      checkScript: 'checks/verify_g0.sh', artifacts: [], lastError: '', blockedReason: '',
      unblockHint: 'network/gh available: git submodule add + gh repo create succeed', verifiedAt: null,
    },
    {
      id: 'g1', title: 'oss-discovery: DECISIONS.json + DATASETS.json (pinned OSS stack + data)',
      status: 'pending', dependsOn: ['g0'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'DECISIONS.json pins every pipeline stage with LIVE-verified URL + license + (where downloadable) sha256: ASR engine whisper.cpp (ggml-org, exact release/tag); EN ggml models (large-v3 / large-v3-turbo / medium); JA model (kotoba-tech/kotoba-whisper, ReazonSpeech alt); Silero VAD (snakers4/silero-vad); offline TTS Piper (rhasspy/piper) JA+EN voices; the ~3B structuring model reused from core (Granite GGUF); llama.cpp GBNF grammar approach; barcode lib (pyzbar) for later',
        'DATASETS.json pins REAL/public sources (CAP Cancer Protocol templates / eCP, ICCR datasets, JSP structured-reporting refs, SNOMED CT pointer) AND the SYNTHETIC-generation plan (template-driven dictation text + Piper TTS audio). Flags that real grossing AUDIO is unavailable publicly → synthetic bridge',
        'Every URL verified to resolve live (WebFetch/curl); licenses recorded; anything requiring acceptance/registration flagged',
        'checks/verify_g1.sh exists and exits 0 (both JSONs parse; each entry has url+license fields; key URLs resolve)',
      ],
      checkScript: 'checks/verify_g1.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g2', title: 'ASR engine: whisper.cpp built (mac+win) + ggml models fetched',
      status: 'pending', dependsOn: ['g1'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'whisper.cpp fetched + built (or prebuilt release) for macOS arm64 (runs `whisper-cli`/`main --help` exit 0) and staged for win-x64; binaries in src/asr/bin/<os>/',
        'EN ggml model + JA model (kotoba-whisper) downloaded, sha256 match DECISIONS.json, in src/asr/models/',
        'A transcribe wrapper (src/asr/transcribe.sh) runs whisper.cpp on a sample 16kHz WAV and emits transcript JSON',
        'Live transcribe smoke: a short spoken WAV (EN + JA) produces a coherent transcript',
        'checks/verify_g2.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g2.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g3', title: 'Capture: push-to-talk + Silero VAD (anti-hallucination)',
      status: 'pending', dependsOn: ['g1'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/capture/ implements push-to-talk gating + Silero VAD so audio is ONLY passed to ASR while speech is present',
        'THE CRITICAL SAFETY TEST: a silence / long-pause WAV fed through the capture+ASR path yields ZERO transcribed tokens (no fabricated speech). A speech WAV passes through',
        'Foot-pedal / hotkey push-to-talk documented (HID keyboard emulation; no driver); wake-word optional',
        'checks/verify_g3.sh exists and exits 0 (includes the silence→zero-tokens assertion)',
      ],
      checkScript: 'checks/verify_g3.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g4', title: 'data-synthesis: synthetic triples (audio + text, JA+EN)',
      status: 'pending', dependsOn: ['g1'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'BOTH tracks (per decision): (a) synthetic dictation TEXT generated from CAP/ICCR/JSP grossing templates paired with gold structured records; (b) TTS-rendered AUDIO (Piper JA+EN) for those texts → audio→transcript→structured triples in data/synth/',
        '>= 40 triples spanning multiple specimen types, laterality, dimensions, colour, margins, cassette counts, bilingual; each structured record schema-valid',
        'data/templates/ holds the public CAP/ICCR/JSP grossing templates used',
        'checks/verify_g4.sh exists and exits 0 (triple count, schema validity, audio files present + playable duration > 0)',
      ],
      checkScript: 'checks/verify_g4.sh', artifacts: [], lastError: '', blockedReason: '',
      unblockHint: 'Piper voices from DECISIONS.json present in src/asr or data tools; if TTS unavailable, text-only triples still satisfy the text track and audio track marks partial', verifiedAt: null,
    },
    {
      id: 'g5', title: 'Structuring: schema + GBNF grammar + 3B prompt',
      status: 'pending', dependsOn: ['g1'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/schema/grossing_record.schema.json defines the CAP/ICCR + JA synoptic fields (accession, specimen_type, laterality, dimensions_mm, colour, consistency, lesion, margins, pieces, cassettes, transcript_ref)',
        'src/structuring/ has a llama.cpp GBNF grammar forcing valid JSON to that schema, and the 3B structuring prompt that fills fields from a transcript and marks any ungrounded field as VERIFY (never invents); accession comes from barcode input, NOT dictation',
        'Live: running the core 3B (from core/usb_stick/models or a fetched Granite GGUF) via llama.cpp with the grammar on a sample transcript produces a schema-valid record with correct laterality/dimensions/cassette count and VERIFY on missing fields',
        'checks/verify_g5.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g5.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g6', title: 'Verify UI: transcript-beside-draft + safety cross-checks',
      status: 'pending', dependsOn: ['g0'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/ui/ builds (reusing core/src/ui/build_ui.sh pattern) a single-file offline UI: operator login, a record/push-to-talk control, VERBATIM transcript shown beside the auto-structured draft, per-field edit, laterality confirm + cassette-count-vs-printer cross-check flags, sign button',
        'Fully self-contained: grep for external https?:// (excluding 127.0.0.1) returns zero',
        'checks/verify_g6.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g6.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g7', title: 'Gateway wiring (auditgw + ASR + LLM) + launchers',
      status: 'pending', dependsOn: ['g2', 'g5', 'g6'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/gateway/ wires the core auditgw (from core/ submodule) to serve the UI + proxy the ASR (whisper.cpp) and the LLM (llama.cpp) on 127.0.0.1 only, and to hash-chain log every grossing session bound to the accession',
        'Launchers (reuse core launcher pattern) START/STOP for mac + win start the whole pipeline with no install',
        'End-to-end local run reachable; audit chain verifies; bash -n passes on launchers; no absolute dev paths',
        'checks/verify_g7.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g7.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g8', title: 'Local end-to-end smoke on synthetic audio',
      status: 'pending', dependsOn: ['g2', 'g3', 'g4', 'g5', 'g6', 'g7'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'tests/smoke_e2e.sh exits 0: a synthetic dictation WAV → capture(PTT/VAD) → whisper.cpp transcript → 3B structured draft (schema-valid) → audit entry that verifies; measured against the paired gold record',
        'THE SAFETY TEST re-run end-to-end: silence WAV under PTT → zero transcribed tokens → no fabricated record',
        'checks/smoke_e2e.sh (or tests/) referenced by verify_g8.sh which exits 0',
      ],
      checkScript: 'checks/verify_g8.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g9', title: 'Training kits prepared + local smoke (ASR LoRA + 3B SFT)',
      status: 'pending', dependsOn: ['g4', 'g5'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'training/asr_lora/ = Whisper LoRA kit (dataset prep from data/synth audio→transcript, train script, config, pinned requirements, REMOTE_RECIPE.md for RunPod, convert-to-ggml step) — NEW',
        'training/llm_sft/ = 3B structuring SFT kit adapting core/training (prep transcript→JSON, train config, convert to GGUF Q4_K_M)',
        'python -m compileall passes on all kit scripts; a TINY local smoke (few steps) runs on synth data for whichever fits local hardware, else documents the RunPod-only path',
        'checks/verify_g9.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g9.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g10', title: 'RunPod training (BLOCKED until connectivity)',
      status: 'pending', dependsOn: ['g9'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'PRECONDITION: runpodConnectivity flag is true in STATE (user supplied RunPod endpoint+key). If false → return status=blocked immediately (do NOT attempt)',
        'Both fine-tunes run on RunPod per REMOTE_RECIPE: Whisper LoRA (audio→transcript) and 3B structuring SFT (transcript→JSON) on the gold/synth data',
        'Tuned artifacts pulled back (weights only): tuned ggml for whisper.cpp + tuned GGUF Q4_K_M for llama.cpp, sha256 recorded, re-pinned in DECISIONS.json',
        'checks/verify_g10.sh exists and exits 0 (or documents blocked)',
      ],
      checkScript: 'checks/verify_g10.sh', artifacts: [], lastError: '', blockedReason: '',
      unblockHint: 'user provides RunPod endpoint + API key and it is recorded so runpodConnectivity=true (force with args {"milestone":"g10"} after providing it)', verifiedAt: null,
    },
    {
      id: 'g11', title: 'grossing-eval vs gold + baseline',
      status: 'pending', dependsOn: ['g8'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'tests/eval.py (or .sh) computes on the synth gold triples (hospital gold later): ASR WER, ZERO-tolerance hallucination rate under push-to-talk, field-level accuracy (laterality, dimensions, cassette count), end-to-end structured-record accuracy vs gold',
        'evals/grossing_results.md records per-metric numbers for out-of-box vs (if g10 done) tuned models, plus estimated secretary edit-rate/time vs manual baseline, with the go/no-go read',
        'checks/verify_g11.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g11.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'g12', title: 'Final validation + MANIFEST + push',
      status: 'pending', dependsOn: ['g2', 'g3', 'g4', 'g5', 'g6', 'g7', 'g8', 'g9', 'g11'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'checks/final_validate.sh exits 0: every checks/verify_g*.sh that is not blocked passes; MANIFEST.sha256 regenerated + verifies; zero external URLs in the packaged UI; no dev-machine absolute paths in shipped code',
        'Repo committed and pushed to the sovereign-grossing-voice GitHub repo (models/binaries/audio/venv gitignored)',
        'checks/verify_g12.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_g12.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
  ],
}

const CONTEXT = [
  '=== SOVEREIGN GROSSING VOICE BUILD ===',
  'GOAL: ' + INITIAL_STATE.goal,
  'NEW REPO ROOT: ' + ROOT + '  (SEPARATE from the core). STATE: ' + STATE + ', LEDGER: ' + LEDGER + '.',
  'SHARED CORE (reused as git submodule at ' + ROOT + '/core): ' + CORE + ' — provides src/auditgw (Go hash-chain gateway), src/launchers (no-install launcher pattern), src/ui/build_ui.sh (single-file offline UI inliner), training/ (QLoRA + REMOTE_RECIPE), and the workflow patterns. REUSE these, do not rewrite them.',
  'PIPELINE: push-to-talk mic + Silero VAD → whisper.cpp ASR (JA/EN, offline) → ~3B LLM structuring (GBNF grammar → CAP/ICCR synoptic JSON, unfilled fields → VERIFY) → secretary verifies transcript-beside-draft → auditgw hash-chain log, accession-bound. 127.0.0.1 only; no PHI leaves the machine; advisory + human-confirmed (non-device).',
  'THE #1 RISK & LOAD-BEARING DESIGN: whisper hallucinates on silence/pauses; PUSH-TO-TALK + VAD means silence is NEVER transcribed. The silence→zero-tokens test (g3, g8) is mandatory and must pass.',
  'STATUS VOCAB: pending -> in_progress -> built -> verified; detours failed (retry to maxAttempts) and blocked (needs user; carries blockedReason + unblockHint). in_progress on a partial download is progress, not a failure.',
  'SAFETY RAILS:',
  '1. Only the Record agent writes STATE.json and ledger.ndjson. Builders/verifiers never touch them.',
  '2. Downloads: check final file first (size+sha good => skip); curl -L --fail -C - into a .part then verify sha256 then mv. Never re-download verified files. Check free disk before multi-GB pulls.',
  '3. NEVER delete anything under ' + ROOT + ' or ' + CORE + ' or outside them. Rebuilds write temp then mv.',
  '4. Everything offline at runtime; servers bind 127.0.0.1 only; no PHI (audio or text) egress.',
  '5. Timestamps only via `date -u +%Y-%m-%dT%H:%M:%SZ`.',
  '6. RunPod (g10) stays BLOCKED until runpodConnectivity is true; do not attempt remote training before then.',
  '=== END CONTEXT ===',
].join('\n')

const SELECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['bootstrapped', 'goalComplete', 'allNonBlockedVerified', 'stalled', 'eligible', 'inProgress', 'blocked', 'exhausted', 'summary'],
  properties: {
    bootstrapped: { type: 'boolean' }, goalComplete: { type: 'boolean' },
    allNonBlockedVerified: { type: 'boolean' }, stalled: { type: 'boolean' },
    eligible: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      required: ['id', 'title', 'definitionOfDone', 'checkScript', 'dependsOn', 'status', 'attempts', 'networkHeavy', 'lastError'],
      properties: {
        id: { type: 'string' }, title: { type: 'string' },
        definitionOfDone: { type: 'array', items: { type: 'string' } },
        checkScript: { type: ['string', 'null'] }, dependsOn: { type: 'array', items: { type: 'string' } },
        status: { type: 'string' }, attempts: { type: 'number' }, networkHeavy: { type: 'boolean' }, lastError: { type: 'string' },
      },
    } },
    inProgress: { type: 'array', items: { type: 'string' } },
    blocked: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      required: ['id', 'blockedReason', 'unblockHint'],
      properties: { id: { type: 'string' }, blockedReason: { type: 'string' }, unblockHint: { type: 'string' } },
    } },
    exhausted: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}

const BUILD_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'status', 'claimedChecks', 'artifacts', 'notes', 'blockedReason'],
  properties: {
    id: { type: 'string' }, status: { type: 'string', enum: ['built', 'in_progress', 'failed', 'blocked'] },
    claimedChecks: { type: 'array', items: { type: 'string' } },
    artifacts: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['path', 'sha256', 'bytes'],
      properties: { path: { type: 'string' }, sha256: { type: 'string' }, bytes: { type: 'number' } },
    } },
    notes: { type: 'string' }, blockedReason: { type: 'string' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'overall', 'checks', 'failureReason'],
  properties: {
    id: { type: 'string' }, overall: { type: 'string', enum: ['pass', 'fail'] },
    checks: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['check', 'status', 'evidence'],
      properties: { check: { type: 'string' }, status: { type: 'string', enum: ['pass', 'fail'] }, evidence: { type: 'string' } },
    } },
    failureReason: { type: 'string' },
  },
}

const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verifiedCount', 'totalCount', 'iterationSummary', 'nextUp', 'blocked', 'action'],
  properties: {
    verifiedCount: { type: 'number' }, totalCount: { type: 'number' }, iterationSummary: { type: 'string' },
    nextUp: { type: 'array', items: { type: 'string' } },
    blocked: { type: 'array', items: {
      type: 'object', additionalProperties: false, required: ['id', 'reason', 'userAction'],
      properties: { id: { type: 'string' }, reason: { type: 'string' }, userAction: { type: 'string' } },
    } },
    action: { type: 'string', enum: ['CONTINUE', 'RUN_GROSSING_VERIFY', 'STOP_LOOP', 'STOP_LOOP_BLOCKED'] },
  },
}

function pickWave(eligible) {
  const ordered = eligible.slice().sort(function (a, b) { return a.id.localeCompare(b.id, 'en', { numeric: true }) })
  const wave = []; let heavy = 0
  for (const m of ordered) {
    if (wave.length >= 3) break
    if (m.networkHeavy) { if (heavy >= 1) continue; heavy++ }
    wave.push(m)
  }
  return wave
}

// ---------- SELECT ----------
phase('Select')
const sel = await agent(CONTEXT + '\n\nYOU ARE THE SELECT AGENT.\n' +
  '1. If ' + STATE + ' does not exist: create the directory ' + ROOT + ' and write STATE.json EXACTLY from this INITIAL_STATE JSON (verbatim, via Write):\n' +
  JSON.stringify(INITIAL_STATE, null, 2) + '\n' +
  'Also write GOAL.md (goal + milestone table id/title/status) and set bootstrapped=true. If STATE.json exists, set bootstrapped=false and do not modify it.\n' +
  '2. Read ' + STATE + '. goalComplete = (goalStatus === "complete"). allNonBlockedVerified = every milestone is verified OR blocked (nothing pending/failed/in_progress left that is not blocked).\n' +
  '3. eligible = milestones with status in {pending, in_progress} AND every dependsOn verified AND attempts < maxAttempts. For g10, if runpodConnectivity is false treat it as blocked (not eligible).\n' +
  (FORCE_MILESTONE ? '   THE HUMAN FORCED "' + FORCE_MILESTONE + '": treat it eligible regardless of status/attempts (report attempts 0, status pending); note in summary. For g10 the force implies the user has provided RunPod connectivity. Do NOT edit STATE yourself.\n' : '') +
  '4. For each blocked milestone, evaluate its unblockHint with READ-ONLY Bash (ls, df, checking runpodConnectivity). If satisfied, include it in eligible; note it. Do NOT edit STATE.\n' +
  '5. stalled = eligible empty AND not allNonBlockedVerified. inProgress = ids in_progress. List blocked with reasons/hints and exhausted (attempts>=max) ids. summary = one paragraph.\n' +
  'You may ONLY write files during step-1 bootstrap. Otherwise read-only.',
  { label: 'select', phase: 'Select', schema: SELECT_SCHEMA })

if (!sel) throw new Error('Select agent failed')
log('Select: ' + sel.summary)
if (sel.goalComplete) return { action: 'STOP_LOOP', goalComplete: true, summary: sel.summary }
if (sel.allNonBlockedVerified) return { action: 'RUN_GROSSING_VERIFY', summary: 'All non-blocked milestones verified — run grossing-verify next.' }
if (sel.stalled) return { action: 'STOP_LOOP_BLOCKED', blocked: sel.blocked, exhausted: sel.exhausted, summary: sel.summary }

// ---------- BUILD ----------
phase('Build')
const wave = pickWave(sel.eligible)
log('Building wave: ' + wave.map(function (m) { return m.id }).join(', '))
const builds = (await parallel(wave.map(function (m) {
  return function () {
    return agent(CONTEXT + '\n\nYOU ARE THE BUILDER for milestone ' + m.id + ': ' + m.title + '\n' +
      'DEFINITION OF DONE (every item must hold when you claim built):\n' +
      m.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
      (m.lastError ? 'YOUR PREDECESSOR FAILED with: "' + m.lastError + '" - diagnose and do it differently.\n' : '') +
      'RULES:\n' +
      '- Do NOT write STATE.json or ledger.ndjson (the Record agent owns them).\n' +
      '- Also write/refresh ' + (m.checkScript || ('checks/verify_' + m.id + '.sh')) + ' so it mechanically re-tests the DoD (executable, exit 0 = pass). A trivially-passing script is a FAIL.\n' +
      '- Reuse the core submodule (' + ROOT + '/core, source ' + CORE + ') for auditgw, launchers, build_ui.sh, training — do not rewrite them.\n' +
      '- Downloads: check final target first (size+sha good => skip); curl -L --fail -C - into a .part, verify sha256, then mv. Never re-download verified files. Never delete under ' + ROOT + ' or ' + CORE + '.\n' +
      '- If you cannot finish: return status=blocked (license wall / persistent 404 / RunPod not connected / needs user — fill blockedReason with the exact user action) or status=in_progress (multi-GB download advanced — NOT a failure) or status=failed (diagnose in notes).\n' +
      '- Record produced/downloaded artifacts with real sha256 (shasum -a 256) + byte size.\n' +
      'Return BUILD_RESULT only.',
      { label: 'build:' + m.id, phase: 'Build', schema: BUILD_SCHEMA })
  }
}))).filter(Boolean)

// ---------- VERIFY ----------
phase('Verify')
const builtClaims = builds.filter(function (b) { return b.status === 'built' })
const verdicts = (await parallel(builtClaims.map(function (b) {
  const m = wave.find(function (w) { return w.id === b.id }) || { definitionOfDone: [], checkScript: null }
  return function () {
    return agent(CONTEXT + '\n\nYOU ARE AN ADVERSARIAL VERIFIER for milestone ' + b.id + '. The builder CLAIMS done. Do not trust it.\n' +
      'DEFINITION OF DONE to verify item by item:\n' +
      m.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
      'Builder claims: ' + JSON.stringify(b.claimedChecks) + '\nBuilder artifacts: ' + JSON.stringify(b.artifacts) + '\n' +
      'RULES: READ-ONLY plus test-execution only. You may Read/grep/ls/execute ' + (m.checkScript || 'the DoD commands') + ' and verification commands (shasum, bash -n, whisper.cpp/llama.cpp on samples, the silence->zero-tokens test, git submodule status, gh repo view). You MUST NOT Write/Edit/delete/download.\n' +
      'Re-run EVERY DoD item literally and paste actual command output as evidence. A check script that does not genuinely test the DoD is a FAIL. For g3/g8 the silence->zero-transcribed-tokens assertion is mandatory.\n' +
      'Return per-check verdicts and overall pass/fail.',
      { label: 'verify:' + b.id, phase: 'Verify', schema: VERIFY_SCHEMA })
  }
}))).filter(Boolean)

// ---------- RECORD ----------
phase('Record')
const report = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT - the ONLY agent allowed to write ' + STATE + ' and ' + LEDGER + '.\n' +
  'Read current STATE.json, then apply transitions:\n' +
  (FORCE_MILESTONE ? 'HUMAN FORCE: milestone ' + FORCE_MILESTONE + ' had attempts reset to 0 (persist reset, clear blockedReason/lastError). If it is g10, also set runpodConnectivity=true.\n' : '') +
  '- built + verifier pass -> verified (verifiedAt via `date -u`), merge artifacts.\n' +
  '- built + verifier fail, OR builder failed -> attempts+1, lastError=failureReason/notes, status = attempts>=maxAttempts ? "failed" : "pending".\n' +
  '- builder in_progress -> in_progress, attempts UNCHANGED.\n' +
  '- builder blocked -> blocked, blockedReason from builder, attempts UNCHANGED.\n' +
  '- untouched milestones stay as-is.\n' +
  'Increment loopIteration; set updatedAt (`date -u`). If all milestones verified AND finalVerifyPassed, set goalStatus="complete".\n' +
  'Re-emit the WHOLE STATE.json with Write (preserve untouched fields). Append one NDJSON line per event to ' + LEDGER + ': {ts,event,milestone,status,attempts,note}. Update GOAL.md table.\n' +
  'Compute report: verifiedCount/totalCount; nextUp = eligible ids next iteration; blocked = current blocked with concrete userAction; action = STOP_LOOP if complete, RUN_GROSSING_VERIFY if all-non-blocked verified but finalVerifyPassed false, STOP_LOOP_BLOCKED if nothing eligible next and not all verified, else CONTINUE.\n' +
  'THIS ITERATION RESULTS:\nBUILDS: ' + JSON.stringify(builds) + '\nVERDICTS: ' + JSON.stringify(verdicts),
  { label: 'record', phase: 'Record', schema: REPORT_SCHEMA })

if (!report) throw new Error('Record agent failed - STATE may not reflect this iteration')
log('Iteration done: ' + report.verifiedCount + '/' + report.totalCount + ' verified. ' + report.iterationSummary)
return report
