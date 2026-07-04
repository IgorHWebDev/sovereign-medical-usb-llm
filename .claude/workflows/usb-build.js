export const meta = {
  name: 'usb-build',
  description: 'One iteration of the med-USB autonomous build: bootstrap/read STATE.json, pick eligible milestones, fan out builders, adversarially verify, record.',
  whenToUse: 'Invoked by the /loop driver to advance the disk-on-key medical LLM package build in /Users/osx/Documents/med_l_llm until all milestones verify.',
  phases: [
    { title: 'Select', detail: 'bootstrap STATE.json if missing; compute eligible milestones from the dependency DAG; early-exit if complete or stalled' },
    { title: 'Build', detail: 'parallel builder agents (cap 3; max 1 network-heavy) for eligible milestones' },
    { title: 'Verify', detail: 'independent adversarial verifier per built milestone re-runs every DoD check, read-only' },
    { title: 'Record', detail: 'single serial agent applies all state transitions to STATE.json + ledger.ndjson; returns progress report' },
  ],
}

const ROOT = '/Users/osx/Documents/med_l_llm'
const STATE = ROOT + '/STATE.json'
const LEDGER = ROOT + '/ledger.ndjson'
const FORCE_MILESTONE = (args && args.milestone) || null

const INITIAL_STATE = {
  goal: 'Fully-offline non-Transformer (RWKV-7/Mamba GGUF Q4, 1.5-3.7B, Japanese-capable) medical documentation copilot USB package: llama.cpp engine for win-x64 + mac-arm64, custom offline web UI with JA medical presets, auditgw Go gateway with tamper-evident hash-chain logging, dual no-admin launchers, bilingual docs.',
  goalStatus: 'building',
  finalVerifyPassed: false,
  updatedAt: null,
  loopIteration: 0,
  milestones: [
    {
      id: 'm0', title: 'Research/pin: DECISIONS.json + build/versions.lock',
      status: 'pending', dependsOn: [], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'DECISIONS.json exists at repo root and parses as valid JSON',
        'It pins BOTH models with exact HF repo, exact GGUF filename, direct download URL, expected sha256, expected byte size, license: PRIMARY = RWKV-7 World ~2.9B Q4_K_M (check Mungert/rwkv7-2.9B-world-GGUF and the shoumenchougou/rwkv7-gxx-gguf collection; prefer World over G1-reasoning variants); FALLBACK = ibm-granite/granite-4.0-h-micro-GGUF Q4_K_M. Every sha256 verified LIVE (HF API https://huggingface.co/api/models/<repo>?blobs=true exposes LFS sha256 oids) - never from memory',
        'It pins one llama.cpp release tag with exact asset URLs + sha256s for llama-<TAG>-bin-win-cpu-x64.zip and llama-<TAG>-bin-macos-arm64.tar.gz, verified live against the GitHub release (releases publish checksums; else record the asset ETag/size and note it)',
        'It records: llama-server port range (8080-8099), auditgw UI port range (8180-8199), API shape the UI will call (/v1/chat/completions with fallback /completion for RWKV template issues), and a source URL for every pinned checksum',
        'build/versions.lock exists mirroring all pins in key=value form',
      ],
      checkScript: null, artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm1', title: 'Scaffold: repo + usb_stick/ tree + checks stubs + GOAL.md',
      status: 'pending', dependsOn: ['m0'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'Directories exist: usb_stick/bin/win-x64, usb_stick/bin/mac-arm64, usb_stick/models, usb_stick/ui, usb_stick/audit, usb_stick/docs/LICENSES, build, src/auditgw, src/ui, src/launchers, checks, downloads, tests/prompts',
        'GOAL.md exists with the goal statement and a milestone table (id/title/status)',
        'usb_stick/stick.config stub exists (key=value: default_model, ctx=8192, threads=auto, llm_port_range, ui_port_range, offline_strict=true, no_mmap=true)',
        'usb_stick/README_FIRST.html placeholder exists',
        'checks/verify_m1.sh exists, is executable, and exits 0',
      ],
      checkScript: 'checks/verify_m1.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm2', title: 'Engine binaries: llama.cpp for mac-arm64 (runs) + win-x64 (checksummed)',
      status: 'pending', dependsOn: ['m0', 'm1'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'usb_stick/bin/mac-arm64/llama-server exists, is executable, and `llama-server --version` (or llama-cli --version) exits 0 on this machine, with its dylibs alongside',
        'usb_stick/bin/win-x64/llama-server.exe exists with required DLLs (llama.dll, ggml*.dll) alongside; downloaded archive sha256 matched the pin in DECISIONS.json',
        'Downloaded archives staged in downloads/ (kept for cache); only needed server binaries + libs copied into usb_stick/bin (not the whole toolset)',
        'checks/verify_m2.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_m2.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm3', title: 'Models fetched + verified + live engine gate (DISK GATE >= 15 GB free)',
      status: 'pending', dependsOn: ['m0', 'm1', 'm2'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'PRECONDITION for DOWNLOADS ONLY: >= 15 GB free (df -g /Users/osx/Documents, avail column) before fetching any missing GGUF; if below and a download is needed, return status=blocked. SKIP this gate entirely when both pinned GGUFs already exist in usb_stick/models/ with sha256 matching DECISIONS.json (the gate protects the download, not the finished package)',
        'Both GGUFs exist in usb_stick/models/ and match the pinned byte size AND sha256 from DECISIONS.json (record hashes in artifacts so later loops only size-check)',
        'usb_stick/models/model_meta.json exists: per model - file, sha256, params, arch (rwkv7/mamba2-hybrid), license, chat template mode (chat|raw)',
        'LIVE ENGINE GATE: mac llama-cli loads the RWKV-7 GGUF and produces coherent Japanese for a short test prompt (e.g. answer in Japanese to a one-line instruction). If RWKV-7 fails to load or output is garbage, swap primary/fallback in DECISIONS.json + model_meta.json and record the swap decision in notes',
        'checks/verify_m3.sh exists and exits 0 (size + recorded-hash check; not a full re-hash)',
      ],
      checkScript: 'checks/verify_m3.sh', artifacts: [], lastError: '', blockedReason: '',
      unblockHint: 'df -g /Users/osx/Documents shows >= 15 GB available; alternatively a matching *.gguf placed manually in downloads/ satisfies the fetch step for that model', verifiedAt: null,
    },
    {
      id: 'm4', title: 'auditgw: Go gateway built for both OSes + hash-chain unit test',
      status: 'pending', dependsOn: ['m0', 'm1'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'Go toolchain available (if `which go` fails, run `brew install go` - the user pre-approved this one-time install)',
        'src/auditgw/ is a Go module (stdlib only, CGO_ENABLED=0) implementing: serve static UI dir on 127.0.0.1:<uiport>; reverse-proxy /v1/* and /completion to llama-server 127.0.0.1:<llmport> with streaming-safe tee (hash the reassembled SSE text, not raw bytes); require X-Operator-Id header on inference routes else 401 JSON error; append hash-chained JSONL per completed inference to <stick>/audit/audit-YYYYMM.jsonl with fields {seq, ts_utc, operator_id, model_file, model_sha256, prompt_sha256, response_sha256, params, prev_hash, entry_hash} where entry_hash = SHA256 of canonical JSON minus entry_hash; genesis entry with stick build id; `auditgw verify <file>` subcommand exits nonzero on any broken link; offline check (refuse/warn if a default route exists unless --allow-online, exposed via /api/status); --spawn-llm mode that launches and supervises llama-server itself; /api/shutdown for graceful exit',
        'usb_stick/bin/mac-arm64/auditgw exists and `auditgw -h` exits 0; usb_stick/bin/win-x64/auditgw.exe exists and `file` reports PE32+ x86-64 (GOOS=windows GOARCH=amd64)',
        'checks/verify_m4.sh exists and exits 0: appends 3 entries to a temp chain via the mac binary, verify passes; flips one byte in a copy, verify FAILS on the copy',
      ],
      checkScript: 'checks/verify_m4.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm5', title: 'Custom web UI: single-file offline, JA medical presets, operator capture',
      status: 'pending', dependsOn: ['m1'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/ui/presets.json is the source of truth: presets for taiin-summary (retirement/discharge summary), operative note, nursing record, referral letter, de-identification assist - each {id, label_ja, label_en, system_prompt (with few-shot skeleton scaffolding in Japanese), input_fields, template_mode: chat|raw, stop[]}; the de-id preset output must carry the caveat that recall is not legal-grade and a human must verify',
        'usb_stick/ui/index.html is fully self-contained (all CSS/JS inline, presets inlined by src/ui/build_ui.sh): operator login view (name + staff id + role -> sessionStorage -> X-Operator-Id header on every request), preset picker (JA-first labels, EN toggle), streaming chat pane with model selector and tok/s display from llama-server timings, audit/offline status banner fed by /api/status',
        'grep -E "https?://" across usb_stick/ui returns zero hits outside 127.0.0.1/localhost references',
        'checks/verify_m5.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_m5.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm6', title: 'Dual launchers: START_MAC.command + START_WINDOWS.bat (+ STOP)',
      status: 'pending', dependsOn: ['m1', 'm2', 'm4'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'src/launchers/ sources exist and are copied to usb_stick/START_MAC.command, usb_stick/START_WINDOWS.bat, usb_stick/STOP_MAC.command, usb_stick/STOP_WINDOWS.bat',
        'Mac launcher: resolves its own directory (relative paths only), self-heals quarantine (xattr -dr com.apple.quarantine, errors ignored), RAM check via sysctl hw.memsize (warn < 8 GB), free-port scan in the configured ranges, starts auditgw --spawn-llm (auditgw supervises llama-server), waits on health, opens browser to the UI, traps INT/TERM to kill children and write a session-end audit event',
        'Windows launcher: same logic, ASCII-only, CRLF line endings; auditgw is the process supervisor so the .bat stays trivial; opens browser via start ""; STOP_WINDOWS.bat calls /api/shutdown via curl.exe (present on Win10 1803+) with taskkill fallback',
        'bash -n passes on the .command files; grep for /Users/ inside any launcher returns nothing; file(1) confirms .bat files are ASCII with CRLF',
        'checks/verify_m6.sh exists and exits 0 (static checks only; live launch is m7)',
      ],
      checkScript: 'checks/verify_m6.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm7', title: 'macOS end-to-end smoke test + Japanese bake-off',
      status: 'pending', dependsOn: ['m2', 'm3', 'm4', 'm5', 'm6'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'tests/prompts/discharge_summary_ja.json exists: structured fake patient course in Japanese + required output section headers to assert (shape assertions, not content)',
        'checks/smoke_mac.sh exists and exits 0: creates/attaches an exFAT sparseimage via hdiutil, rsyncs usb_stick/ onto it, launches from the image via the real START_MAC.command path (or its extracted logic), polls health OK, POSTs the discharge-summary case through auditgw, asserts non-empty Japanese output containing required section headers, records tok/s from timings, asserts the audit chain grew >= 1 entry and `auditgw verify` passes, tamper test (flip one byte in a copy -> verify fails), clean shutdown with no orphan llama-server/auditgw processes, detaches the image',
        'tests/bakeoff_ja.sh exists and has been run: all 5 presets x both models, outputs + tok/s written to tests/bakeoff_results.md for the human to pick default_model (report the recommendation but do not require the human pick to pass this milestone)',
      ],
      checkScript: 'checks/smoke_mac.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm8', title: 'Bilingual docs + Windows manual checklist + licenses',
      status: 'pending', dependsOn: ['m5', 'm6'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'usb_stick/docs/ contains QUICKSTART_EN.md, QUICKSTART_JA.md (clinician-level, 3 steps), ENCRYPTION_NOTE_EN.md + _JA.md (hardware-keypad drive recommendation e.g. IronKey Vault Privacy 80ES / Apricorn Aegis; VeraCrypt rejected - needs admin driver; BitLocker-To-Go rejected - no macOS; exFAT rationale; drive custody register requirement), WINDOWS_VALIDATION_CHECKLIST.md (numbered manual test steps for the first real Windows PC incl. SmartScreen guidance), CUSTODY_REGISTER_TEMPLATE.md',
        'usb_stick/docs/LICENSES/ contains Apache-2.0 texts + model card notes + llama.cpp MIT + a disclaimer: advisory drafting tool, no clinical validation, physician confirms every output (PMDA non-device posture)',
        'usb_stick/README_FIRST.html is bilingual EN/JA, renders offline, links only to files that exist on the stick',
        'checks/verify_m8.sh exists and exits 0 (existence + link-check: every relative path referenced in docs resolves)',
      ],
      checkScript: 'checks/verify_m8.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm9', title: 'Final package validation + MANIFEST.sha256',
      status: 'pending', dependsOn: ['m2', 'm3', 'm4', 'm5', 'm6', 'm7', 'm8'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'checks/final_validate.sh exists and exits 0: every checks/verify_m*.sh passes; usb_stick/MANIFEST.sha256 regenerated (every file except MANIFEST itself and audit/*.jsonl) and verifies; total usb_stick/ size reported and < 28 GB (32 GB stick with margin); grep -r "/Users/" usb_stick/ returns nothing (excluding MANIFEST); a fresh genesis audit entry embeds the manifest hash',
      ],
      checkScript: 'checks/final_validate.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm10', title: 'Datasets: open Japanese medical eval + SFT corpora researched, license-verified, fetched',
      status: 'pending', dependsOn: ['m0'], attempts: 0, maxAttempts: 3, networkHeavy: true,
      definitionOfDone: [
        'Internet research performed LIVE (WebSearch/WebFetch/curl - never from memory): identify open Japanese medical datasets suitable for (a) EVALUATION - candidates to verify: IgakuQA (JP medical licensing exam QA), JMedBench, JMMLU medical subsets - and (b) SFT INSTRUCTION TUNING - open Japanese medical instruction/QA corpora (e.g. ApolloCorpus JA portions, llm-jp medical instruction sets, or better candidates found in research). Verify every URL resolves and read the actual license text live',
        'DATASETS.json at repo root pins >= 1 eval benchmark AND >= 1 SFT-usable corpus: exact download URL, license (must permit local research use; record any commercial-use or redistribution caveats explicitly), size, format, anonymization status (exam-derived / synthetic / de-identified are acceptable; datasets containing raw PHI are FORBIDDEN - reject and note), citation, and sha256 after download',
        'DISK GATE (downloads only): >= 10 GB free (df -g /Users/osx/Documents) before fetching; skip gate if files already downloaded and hash-matched. Datasets downloaded to datasets/eval/ and datasets/sft/ via the standard downloads/*.part staging; sha256s recorded in DATASETS.json',
        'checks/verify_m10.sh exists and exits 0: DATASETS.json parses, every entry has url+license+anonymization+sha256 fields, downloaded files exist and match recorded sizes/hashes',
      ],
      checkScript: 'checks/verify_m10.sh', artifacts: [], lastError: '', blockedReason: '',
      unblockHint: 'df -g /Users/osx/Documents shows >= 10 GB available; alternatively dataset files placed manually in datasets/eval/ and datasets/sft/ satisfy the fetch step', verifiedAt: null,
    },
    {
      id: 'm11', title: 'Baseline eval harness: both shipped GGUFs scored on a JA medical benchmark',
      status: 'pending', dependsOn: ['m3', 'm10'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'tests/eval_ja_med.py (or .sh) runs a FIXED, seed-stable subset (>= 50 items, exact item ids recorded) of the pinned eval benchmark against BOTH GGUFs via the shipped mac llama-server (temperature 0), scoring accuracy on choice questions and/or format adherence on generative items',
        'evals/baseline_results.json + evals/baseline_results.md record per-model scores, item counts, tok/s, runtime, and the subset item ids so the run is reproducible',
        'Honest framing required in the .md: 2-3B general-purpose models are expected to score far below medical-tuned large models; these numbers are the yardstick for measuring future fine-tunes, not a clinical-capability claim',
        'checks/verify_m11.sh exists and exits 0: re-runs a 5-item live smoke subset through llama-server and confirms both results files parse and contain entries for both models',
      ],
      checkScript: 'checks/verify_m11.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
    {
      id: 'm12', title: 'Fine-tuning pipeline: LoRA/SFT kit + local smoke run (or validated remote GPU recipe)',
      status: 'pending', dependsOn: ['m10', 'm11'], attempts: 0, maxAttempts: 3, networkHeavy: false,
      definitionOfDone: [
        'training/ contains a complete SFT/LoRA kit for a chosen target model (prefer the stick default granite-4.0-h-micro; document the RWKV-7 alternative via its native RWKV-LM trainer): dataset prep script (DATASETS.json sft corpus -> chat-format JSONL), training script + config, pinned requirements, and TRAINING.json recording the framework choice (mlx-lm / PyTorch-MPS / RWKV-LM) with LIVE-verified support for the target architecture',
        'FEASIBILITY BRANCH, machine-checkable either way: (a) if local hardware suffices (check sysctl hw.memsize RAM and framework arch support), run a smoke LoRA: >= 10 optimizer steps on >= 32 real SFT examples from datasets/sft/, saving the adapter artifact + a loss log showing finite, decreasing loss; OR (b) if infeasible, training/REMOTE_RECIPE.md plus a validated kit (python -m compileall passes on all kit scripts, requirements pinned with versions) for an off-site GPU run. checks/verify_m12.sh must pass whichever branch was taken and print which branch',
        'If an adapter was produced: document and attempt the adapter->GGUF merge/convert path; run a 20-item eval comparison vs baseline into evals/tuned_vs_baseline.md (pipeline proof only - no quality bar required; real gains need the hospital gold set + GPU)',
        'training/README_TRAINING.md documents the real hospital path per the FDE proposal: gold-set acquisition via the AI Medical Centre / Data Access Review Committee, off-site GPU SFT on de-identified data ONLY, re-quantize to GGUF, re-pin in DECISIONS.json, then re-run m7 bake-off and m9 validation before any tuned model ships on the stick',
        'checks/verify_m12.sh exists and exits 0',
      ],
      checkScript: 'checks/verify_m12.sh', artifacts: [], lastError: '', blockedReason: '', unblockHint: '', verifiedAt: null,
    },
  ],
}

const CONTEXT = [
  '=== MED-USB BUILD CONTEXT ===',
  'GOAL: ' + INITIAL_STATE.goal,
  'REPO ROOT: ' + ROOT + '  (STATE: ' + STATE + ', LEDGER: ' + LEDGER + ')',
  'LAYOUT: build/ (fetch+assemble scripts, versions.lock), src/auditgw (Go), src/ui, src/launchers, usb_stick/ (the shippable tree), checks/ (one verify script per milestone, exit 0 = pass), downloads/ (resumable staging), tests/.',
  'STATUS VOCABULARY: pending -> in_progress -> built -> verified; detours: failed (attempt failed), blocked (needs the user; carries blockedReason + unblockHint). in_progress on a partial download is progress, NOT a failure.',
  'REFERENCE RESEARCH (read-only): /Users/osx/Documents/fde_dep/fde_platform/engagements/keio-osaka-hospitals/ - esp. 05_selfhosted_models_research.md, selfhosted_research_raw/iter4-res-r44 (audit mandate), r45 (de-id recall caveat), r46 (1.5-3.7B tier rule).',
  'SAFETY RAILS (absolute):',
  '1. Only the Record agent writes STATE.json and ledger.ndjson. Builders and verifiers NEVER touch them.',
  '2. Download discipline: check the final file first (size+sha already good => skip); curl -L --fail -C - into downloads/<name>.part, verify sha256, then mv into place. NEVER re-download a verified file. Check free disk before any multi-GB pull.',
  '3. NEVER delete anything under usb_stick/, downloads/, or outside ' + ROOT + '. Rebuilds write to a temp name then mv over.',
  '4. Hospital constraint: the stick must run with NO installation and NO admin rights on host PCs; everything on the stick uses relative paths; servers bind 127.0.0.1 only.',
  '5. Timestamps only via `date -u +%Y-%m-%dT%H:%M:%SZ` in Bash.',
  '=== END CONTEXT ===',
].join('\n')

const SELECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['bootstrapped', 'goalComplete', 'allMilestonesVerified', 'stalled', 'eligible', 'inProgress', 'blocked', 'exhausted', 'summary'],
  properties: {
    bootstrapped: { type: 'boolean' },
    goalComplete: { type: 'boolean' },
    allMilestonesVerified: { type: 'boolean' },
    stalled: { type: 'boolean' },
    eligible: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'title', 'definitionOfDone', 'checkScript', 'dependsOn', 'status', 'attempts', 'networkHeavy', 'lastError'],
        properties: {
          id: { type: 'string' }, title: { type: 'string' },
          definitionOfDone: { type: 'array', items: { type: 'string' } },
          checkScript: { type: ['string', 'null'] },
          dependsOn: { type: 'array', items: { type: 'string' } },
          status: { type: 'string' }, attempts: { type: 'number' },
          networkHeavy: { type: 'boolean' }, lastError: { type: 'string' },
        },
      },
    },
    inProgress: { type: 'array', items: { type: 'string' } },
    blocked: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'blockedReason', 'unblockHint'],
        properties: { id: { type: 'string' }, blockedReason: { type: 'string' }, unblockHint: { type: 'string' } },
      },
    },
    exhausted: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}

const BUILD_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'status', 'claimedChecks', 'artifacts', 'notes', 'blockedReason'],
  properties: {
    id: { type: 'string' },
    status: { type: 'string', enum: ['built', 'in_progress', 'failed', 'blocked'] },
    claimedChecks: { type: 'array', items: { type: 'string' } },
    artifacts: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['path', 'sha256', 'bytes'],
        properties: { path: { type: 'string' }, sha256: { type: 'string' }, bytes: { type: 'number' } },
      },
    },
    notes: { type: 'string' },
    blockedReason: { type: 'string' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'overall', 'checks', 'failureReason'],
  properties: {
    id: { type: 'string' },
    overall: { type: 'string', enum: ['pass', 'fail'] },
    checks: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['check', 'status', 'evidence'],
        properties: { check: { type: 'string' }, status: { type: 'string', enum: ['pass', 'fail'] }, evidence: { type: 'string' } },
      },
    },
    failureReason: { type: 'string' },
  },
}

const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verifiedCount', 'totalCount', 'iterationSummary', 'nextUp', 'blocked', 'action'],
  properties: {
    verifiedCount: { type: 'number' },
    totalCount: { type: 'number' },
    iterationSummary: { type: 'string' },
    nextUp: { type: 'array', items: { type: 'string' } },
    blocked: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'reason', 'userAction'],
        properties: { id: { type: 'string' }, reason: { type: 'string' }, userAction: { type: 'string' } },
      },
    },
    action: { type: 'string', enum: ['CONTINUE', 'RUN_USB_VERIFY', 'STOP_LOOP', 'STOP_LOOP_BLOCKED'] },
  },
}

function pickWave(eligible) {
  const ordered = eligible.slice().sort(function (a, b) { return a.id.localeCompare(b.id, 'en', { numeric: true }) })
  const wave = []
  let heavy = 0
  for (const m of ordered) {
    if (wave.length >= 3) break
    if (m.networkHeavy) {
      if (heavy >= 1) continue
      heavy++
    }
    wave.push(m)
  }
  return wave
}

// ---------- SELECT ----------
phase('Select')
const sel = await agent(CONTEXT + '\n\nYOU ARE THE SELECT AGENT.\n' +
  '1. If ' + STATE + ' does not exist: create the directories ' + ROOT + '/{checks,downloads,build,src,usb_stick,tests}, write STATE.json EXACTLY from this INITIAL_STATE JSON (verbatim, via Write):\n' +
  JSON.stringify(INITIAL_STATE, null, 2) + '\n' +
  'Also write GOAL.md (goal statement + milestone table with id/title/status) and set bootstrapped=true in your answer. If STATE.json exists, set bootstrapped=false and do not modify it.\n' +
  '2. Read ' + STATE + '. goalComplete = (goalStatus === "complete"). allMilestonesVerified = every milestone status === "verified".\n' +
  '3. eligible = milestones with status in {pending, in_progress} AND every dependsOn milestone verified AND attempts < maxAttempts.\n' +
  (FORCE_MILESTONE
    ? '   THE HUMAN FORCED "' + FORCE_MILESTONE + '": treat it as eligible regardless of its current status/attempts (report its attempts as 0 and status as pending in your answer); include a note in summary. Do NOT edit STATE.json yourself - the Record agent will persist the reset.\n'
    : '') +
  '4. For each milestone with status blocked: evaluate its unblockHint with READ-ONLY Bash (df, ls, shasum). If the hint is now satisfied, include the milestone in eligible (status pending, keep attempts) and note it in summary. Do NOT edit STATE.json.\n' +
  '5. stalled = (eligible is empty AND not allMilestonesVerified) - i.e. everything remaining is blocked or exhausted (attempts >= maxAttempts). List blocked milestones with reasons/hints and exhausted milestone ids.\n' +
  '6. inProgress = ids currently in_progress. summary = one paragraph of overall state.\n' +
  'You may ONLY write files during step 1 bootstrap. Otherwise read-only.',
  { label: 'select', phase: 'Select', schema: SELECT_SCHEMA })

if (!sel) throw new Error('Select agent failed')
log('Select: ' + sel.summary)

if (sel.goalComplete) {
  return { action: 'STOP_LOOP', goalComplete: true, summary: sel.summary }
}
if (sel.allMilestonesVerified) {
  return { action: 'RUN_USB_VERIFY', summary: 'All milestones verified - run the usb-verify workflow next iteration for the final end-to-end gate.' }
}
if (sel.stalled) {
  return { action: 'STOP_LOOP_BLOCKED', blocked: sel.blocked, exhausted: sel.exhausted, summary: sel.summary }
}

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
      '- Also write/refresh ' + (m.checkScript || ('checks/verify_' + m.id + '.sh')) + ' so it mechanically re-tests the DoD (executable, exit 0 = pass). A trivially-passing script will be treated as a FAIL by the verifier.\n' +
      '- Downloads: check the final target first (size+sha already good => skip); curl -L --fail -C - into downloads/<name>.part, verify sha256, then mv. Never re-download verified files. Never delete under downloads/ or usb_stick/.\n' +
      '- If you cannot finish: return status=blocked (license wall, persistent 404, disk gate, needs user - fill blockedReason with the exact user action) or status=in_progress (multi-GB download partially advanced - NOT a failure) or status=failed (genuine error - fill notes with diagnosis).\n' +
      '- Record every produced/downloaded artifact with real sha256 (shasum -a 256) and byte size.\n' +
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
    return agent(CONTEXT + '\n\nYOU ARE AN ADVERSARIAL VERIFIER for milestone ' + b.id + '. The builder CLAIMS it is done. Do not trust it.\n' +
      'DEFINITION OF DONE to verify item by item:\n' +
      m.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
      'Builder claims: ' + JSON.stringify(b.claimedChecks) + '\nBuilder artifacts: ' + JSON.stringify(b.artifacts) + '\n' +
      'RULES: READ-ONLY plus test-execution only. You may Read/grep/ls freely and EXECUTE ' + (m.checkScript || 'the DoD commands') + ' and verification commands (shasum, bash -n, file, curl to 127.0.0.1 during a smoke run, launching/killing the local test servers where the DoD requires it). You MUST NOT Write/Edit/delete/download anything.\n' +
      'Re-run EVERY DoD item literally and paste actual command output snippets as evidence. Inspect the check script source: if it does not genuinely test the DoD (rubber stamp), that is itself a FAIL.\n' +
      'Return a verdict per check and overall pass/fail.',
      { label: 'verify:' + b.id, phase: 'Verify', schema: VERIFY_SCHEMA })
  }
}))).filter(Boolean)

// ---------- RECORD ----------
phase('Record')
const report = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT - the ONLY agent allowed to write ' + STATE + ' and ' + LEDGER + '.\n' +
  'Read the current STATE.json, then apply these transitions from this iteration:\n' +
  (FORCE_MILESTONE ? 'HUMAN FORCE: milestone ' + FORCE_MILESTONE + ' had attempts reset to 0 this iteration (persist that reset, clear blockedReason/lastError, before applying its result below).\n' : '') +
  '- built + verifier overall=pass -> status=verified, set verifiedAt (`date -u +%Y-%m-%dT%H:%M:%SZ`), merge builder artifacts into the milestone artifacts.\n' +
  '- built + verifier overall=fail, OR builder status=failed -> attempts+1, lastError = failureReason or builder notes, status = (attempts >= maxAttempts ? "failed" : "pending").\n' +
  '- builder status=in_progress -> status=in_progress, attempts UNCHANGED, note progress in lastError-free notes.\n' +
  '- builder status=blocked -> status=blocked, blockedReason from builder, attempts UNCHANGED.\n' +
  '- Milestones not touched this iteration stay exactly as they are.\n' +
  'Then: increment loopIteration; set updatedAt (`date -u`). If ALL milestones are verified AND finalVerifyPassed is true, set goalStatus="complete".\n' +
  'Re-emit the WHOLE STATE.json with Write, preserving untouched fields exactly. Append one NDJSON line per event to ' + LEDGER + ': {"ts":"<date -u>","event":"BUILD|VERIFY|BLOCKED|FAILED|VERIFIED|FORCED","milestone":"mN","status":"...","attempts":N,"note":"..."}. Update the milestone table in GOAL.md.\n' +
  'Then compute the report: verifiedCount/totalCount over all milestones; nextUp = eligible ids for the NEXT iteration (deps now satisfied); blocked = current blocked milestones with the concrete userAction from unblockHint; action = STOP_LOOP if goalStatus complete, RUN_USB_VERIFY if all milestones verified but finalVerifyPassed false, STOP_LOOP_BLOCKED if nothing is eligible next and not all verified, else CONTINUE.\n' +
  'THIS ITERATION RESULTS:\nBUILDS: ' + JSON.stringify(builds) + '\nVERDICTS: ' + JSON.stringify(verdicts),
  { label: 'record', phase: 'Record', schema: REPORT_SCHEMA })

if (!report) throw new Error('Record agent failed - STATE.json may not reflect this iteration')
log('Iteration done: ' + report.verifiedCount + '/' + report.totalCount + ' verified. ' + report.iterationSummary)
return report
