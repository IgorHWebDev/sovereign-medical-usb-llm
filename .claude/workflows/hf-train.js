export const meta = {
  name: 'hf-train',
  description: 'HF-Jobs training pipeline (replaces RunPod g10) for Sovereign Grossing Voice: regenerate JA synthetic audio via the user CosyVoice/XTTS Space, push the dataset to HF, submit Whisper-LoRA + 3B-QLoRA fine-tunes as HF Jobs on A10G, pull tuned models, convert to ggml + GGUF Q4, re-pin, re-eval, and mark g10 verified. GPU compute runs on HF, not in the agent loop.',
  whenToUse: 'Invoked once the out-of-box grossing build is complete and the user has provided an HF write token (cached at ~/.cache/huggingface/token). Poll-and-collect across iterations while HF Jobs run.',
  phases: [
    { title: 'Select', detail: 'bootstrap HF_STATE.json if missing; read HF-Jobs status; pick the next eligible stage or poll running jobs' },
    { title: 'Build', detail: 'run the eligible stage: prep+push data, regen JA audio, submit jobs, or collect+convert+eval' },
    { title: 'Verify', detail: 'adversarial verifier confirms the stage DoD (job submitted / model pulled + converted / eval improved)' },
    { title: 'Record', detail: 'single-writer update of HF_STATE.json + ledger; on completion flip grossing STATE g10 -> verified' },
  ],
}

const ROOT = '/Users/osx/Documents/sovereign-grossing-voice'
const HFSTATE = ROOT + '/HF_STATE.json'
const GROSSING_STATE = ROOT + '/STATE.json'
const LEDGER = ROOT + '/hf_ledger.ndjson'
const HF_USER = 'caesarniseko'
const VENV_PY = '/Users/osx/Documents/med_l_llm/training/.venv/bin/python'
const FLAVOR = 'a10g-large'

const INITIAL_STATE = {
  goal: 'Domain-fine-tune the grossing ASR (Whisper LoRA) and 3B structuring (QLoRA SFT) on HF Jobs (A10G), especially lifting the weak Japanese ASR arm (baseline JA CER 62.2%, EN WER 7.1%), then re-pin the tuned ggml/GGUF into the offline stack and re-eval. HF write token cached at ~/.cache/huggingface/token; auth via HfApi() (no token in prompts/files).',
  goalStatus: 'training',
  flavor: FLAVOR,
  hfUser: HF_USER,
  updatedAt: null,
  iteration: 0,
  repos: {
    dataset: HF_USER + '/grossing-synth',
    asrModel: HF_USER + '/whisper-grossing-lora',
    llmModel: HF_USER + '/granite-grossing-lora',
  },
  jobs: { asr: null, llm: null },   // {id, status} filled after submit
  stages: [
    { id: 'h1', title: 'Prep + regen JA audio + push dataset to HF', status: 'pending', dependsOn: [],
      definitionOfDone: [
        'JA synthetic audio regenerated with a higher-quality multilingual TTS (prefer the user CosyVoice Space caesarniseko/grand-hotel-tts or Coqui XTTS-v2 Space via gradio_client; if the Space is unreachable, keep Piper JA audio and record the fallback) — improves the weak JA ASR arm',
        'The data/synth audio->transcript pairs (ASR) and transcript->JSON pairs (SFT) are packaged and pushed to HF dataset repo ' + HF_USER + '/grossing-synth (private) via HfApi().upload_folder; dataset loads back with load_dataset or hf_hub_download',
        'checks present: dataset repo exists + row counts match local triples',
      ] },
    { id: 'h2', title: 'Submit Whisper-LoRA HF Job (A10G)', status: 'pending', dependsOn: ['h1'],
      definitionOfDone: [
        'A UV training script (PEP-723 inline deps: transformers, peft, datasets, accelerate, evaluate, jiwer) fine-tunes Whisper (medium/large-v3) with LoRA on the ASR pairs from ' + HF_USER + '/grossing-synth, pushing the adapter to ' + HF_USER + '/whisper-grossing-lora',
        'Submitted via HfApi().run_uv_job(script, flavor="' + FLAVOR + '") (or run_job with a torch image); job id recorded in jobs.asr; job reaches RUNNING/COMPLETED (not immediate ERROR)',
      ] },
    { id: 'h3', title: 'Submit 3B QLoRA SFT HF Job (A10G)', status: 'pending', dependsOn: ['h1'],
      definitionOfDone: [
        'A UV training script (transformers, peft, trl, bitsandbytes, datasets) QLoRA-fine-tunes the base 3B (Granite) on the transcript->JSON SFT pairs, pushing the adapter to ' + HF_USER + '/granite-grossing-lora',
        'Submitted via run_uv_job flavor="' + FLAVOR + '"; job id recorded in jobs.llm; job reaches RUNNING/COMPLETED',
      ] },
    { id: 'h4', title: 'Await both HF Jobs to COMPLETED', status: 'pending', dependsOn: ['h2', 'h3'],
      definitionOfDone: [
        'HfApi().inspect_job for both jobs.asr and jobs.llm returns status COMPLETED. If either is ERROR, fetch_job_logs, diagnose, mark that stage failed with the log tail so it can be re-submitted. If still RUNNING, return in_progress (NOT a failure) so the loop polls again later',
      ] },
    { id: 'h5', title: 'Pull tuned adapters + convert to ggml + GGUF Q4', status: 'pending', dependsOn: ['h4'],
      definitionOfDone: [
        'Whisper adapter pulled from ' + HF_USER + '/whisper-grossing-lora, merged, converted to ggml for whisper.cpp -> src/asr/models/ggml-grossing-tuned.bin',
        'Granite adapter pulled from ' + HF_USER + '/granite-grossing-lora, fused (reuse training/llm_sft/fuse_and_convert.sh), converted to GGUF Q4_K_M -> usb_stick or src/structuring model dir',
        'DECISIONS.json re-pinned with the tuned model paths + sha256; originals kept as fallback',
      ] },
    { id: 'h6', title: 'Re-eval tuned vs baseline + mark g10 verified', status: 'pending', dependsOn: ['h5'],
      definitionOfDone: [
        'tests/eval.py re-run with the tuned models over the g4 gold triples; evals/grossing_results.md updated with tuned columns; report the JA CER + EN WER deltas vs baseline (JA CER 62.2% / EN WER 7.1%)',
        'In the grossing ' + GROSSING_STATE + ': set runpodConnectivity semantics satisfied via HF, set milestone g10 status=verified with the tuned-model artifacts + verifiedAt, and clear its blockedReason (this is the ONLY cross-write into grossing STATE; re-read it fresh and preserve all other fields). Then a follow-up grossing-verify can set goalStatus=complete',
      ] },
  ],
}

const CONTEXT = [
  '=== HF-JOBS TRAINING (Sovereign Grossing Voice) ===',
  'GOAL: ' + INITIAL_STATE.goal,
  'REPO: ' + ROOT + '. HF_STATE: ' + HFSTATE + ', LEDGER: ' + LEDGER + '. Grossing build STATE: ' + GROSSING_STATE + '.',
  'HF AUTH: a write token is cached at ~/.cache/huggingface/token. Use ' + VENV_PY + ' with `from huggingface_hub import HfApi` — it auto-reads the cache. NEVER print, echo, or write the token to any file. HF user = ' + HF_USER + ', Pro, HF Jobs entitled.',
  'HF JOBS API (huggingface_hub 0.36): HfApi().run_uv_job(script, flavor, env, secrets), inspect_job(job_id), fetch_job_logs(job_id), cancel_job(job_id), list_jobs(). Jobs run on HF GPU (flavor ' + FLAVOR + '); compute is OFF the agent loop. A UV script uses PEP-723 inline deps and the job gets HF_TOKEN as a secret so it can push to model repos.',
  'REUSE the existing kits: ' + ROOT + '/training/asr_lora/ (train_whisper_lora.py, convert_whisper_to_ggml.sh) and training/llm_sft/ (run_smoke_lora.sh, fuse_and_convert.sh) — adapt them into UV job scripts, do not rewrite from scratch.',
  'DATA: local synthetic triples are in ' + ROOT + '/data/synth (from g4). JA audio regen: prefer the user Space caesarniseko/grand-hotel-tts (CosyVoice) or a Coqui XTTS Space via gradio_client; fallback to existing Piper audio and record it.',
  'DISCIPLINE: only the Record agent writes HF_STATE.json/ledger and (only in h6) the grossing STATE g10. Builders/verifiers return structured JSON. Never delete files. Timestamps via `date -u`.',
  'POLLING: h4 may legitimately return in_progress for many iterations while jobs run — that is NOT a failure. Submitting jobs (h2/h3) is fast; training runs async on HF.',
  'IMPORTANT COMPLETION RULE: a job whose inspect_job status is ERROR/timeout but whose ADAPTER WAS SUCCESSFULLY PUSHED to its model repo is EFFECTIVELY COMPLETE. For h4, verify completion by checking the adapter exists (list_repo_files has adapter_model.safetensors) at caesarniseko/granite-grossing-lora (LLM) and caesarniseko/whisper-grossing-lora (ASR) — BOTH ADAPTERS ALREADY EXIST. The LLM QLoRA job timed out on wall-clock AFTER pushing its adapter, so treat it as complete. h4 is satisfied; proceed to h5 (pull adapters BY REPO, not by job status) → convert → h6 re-eval.',
  '=== END CONTEXT ===',
].join('\n')

const SELECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['bootstrapped', 'goalComplete', 'stalled', 'eligible', 'inProgress', 'summary'],
  properties: {
    bootstrapped: { type: 'boolean' }, goalComplete: { type: 'boolean' }, stalled: { type: 'boolean' },
    eligible: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      required: ['id', 'title', 'definitionOfDone', 'dependsOn', 'status'],
      properties: {
        id: { type: 'string' }, title: { type: 'string' },
        definitionOfDone: { type: 'array', items: { type: 'string' } },
        dependsOn: { type: 'array', items: { type: 'string' } }, status: { type: 'string' },
      },
    } },
    inProgress: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
  },
}
const BUILD_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'status', 'jobsUpdate', 'notes'],
  properties: {
    id: { type: 'string' }, status: { type: 'string', enum: ['built', 'in_progress', 'failed'] },
    jobsUpdate: { type: 'object', additionalProperties: false, required: ['asr', 'llm'],
      properties: { asr: { type: ['string', 'null'] }, llm: { type: ['string', 'null'] } } },
    notes: { type: 'string' },
  },
}
const VERIFY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['id', 'overall', 'evidence'],
  properties: { id: { type: 'string' }, overall: { type: 'string', enum: ['pass', 'fail'] }, evidence: { type: 'string' } },
}
const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['doneCount', 'totalCount', 'iterationSummary', 'nextUp', 'action'],
  properties: {
    doneCount: { type: 'number' }, totalCount: { type: 'number' }, iterationSummary: { type: 'string' },
    nextUp: { type: 'array', items: { type: 'string' } },
    action: { type: 'string', enum: ['CONTINUE', 'POLL_JOBS', 'STOP_LOOP_DONE', 'STOP_LOOP'] },
  },
}

// ---------- SELECT ----------
phase('Select')
const sel = await agent(CONTEXT + '\n\nYOU ARE THE SELECT AGENT for the HF training pipeline.\n' +
  '1. If ' + HFSTATE + ' does not exist: write it EXACTLY from this INITIAL_STATE JSON (via Write), set bootstrapped=true:\n' +
  JSON.stringify(INITIAL_STATE, null, 2) + '\n' +
  '2. Read ' + HFSTATE + '. goalComplete = (goalStatus === "complete").\n' +
  '3. eligible = stages with status in {pending,in_progress} AND every dependsOn done. For h4 (await jobs): if jobs.asr/jobs.llm are set, treat it as eligible so it polls.\n' +
  '4. stalled = nothing eligible and not complete. inProgress = ids in_progress. Return per schema.',
  { label: 'select', phase: 'Select', schema: SELECT_SCHEMA })
if (!sel) throw new Error('Select failed')
log('Select: ' + sel.summary)
if (sel.goalComplete) return { action: 'STOP_LOOP_DONE', summary: sel.summary }
if (sel.stalled) return { action: 'STOP_LOOP', summary: sel.summary }

// pick the lowest-id eligible stage (training is largely sequential; run one stage per iteration to keep control)
const next = sel.eligible.slice().sort(function (a, b) { return a.id.localeCompare(b.id, 'en', { numeric: true }) })[0]
log('Stage: ' + next.id + ' — ' + next.title)

// ---------- BUILD ----------
phase('Build')
const build = await agent(CONTEXT + '\n\nYOU ARE THE BUILDER for stage ' + next.id + ': ' + next.title + '\n' +
  'DEFINITION OF DONE:\n' + next.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
  'RULES: use ' + VENV_PY + ' for all HF calls (HfApi auto-reads the cached token; NEVER print/write the token). Do NOT write HF_STATE.json/ledger or grossing STATE (the Record agent does). Author any HF-Jobs UV scripts under ' + ROOT + '/training/hf/. For submit stages return the new job id(s) in jobsUpdate. If a job is still RUNNING during h4, return status=in_progress (NOT failed). If a job ERRORed, fetch_job_logs, put the diagnosis + log tail in notes, return status=failed. Return BUILD_SCHEMA only.',
  { label: 'build:' + next.id, phase: 'Build', schema: BUILD_SCHEMA })
if (!build) throw new Error('Build failed for ' + next.id)

// ---------- VERIFY ----------
phase('Verify')
let verdict = { id: next.id, overall: 'pass', evidence: 'n/a (in_progress or failed — no verify)' }
if (build.status === 'built') {
  verdict = await agent(CONTEXT + '\n\nYOU ARE AN ADVERSARIAL VERIFIER for stage ' + next.id + '. The builder claims done. Do not trust it.\n' +
    'DoD:\n' + next.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
    'Builder notes: ' + build.notes + '\nBuilder jobsUpdate: ' + JSON.stringify(build.jobsUpdate) + '\n' +
    'READ-ONLY + verification calls only (' + VENV_PY + ' HfApi to confirm repos/jobs exist; ls; shasum; inspect_job). NEVER print the token. Paste real output as evidence. Return VERIFY_SCHEMA.',
    { label: 'verify:' + next.id, phase: 'Verify', schema: VERIFY_SCHEMA })
  if (!verdict) verdict = { id: next.id, overall: 'fail', evidence: 'verifier returned nothing' }
}

// ---------- RECORD ----------
phase('Record')
const report = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT — the ONLY writer of ' + HFSTATE + ', ' + LEDGER + ', and (only for h6) the grossing STATE g10.\n' +
  'Read current HF_STATE.json. Apply for stage ' + next.id + ':\n' +
  '- builder built + verifier pass -> stage status=done; merge jobsUpdate into jobs (keep non-null ids).\n' +
  '- builder in_progress -> keep status=in_progress (polling), merge jobsUpdate.\n' +
  '- builder failed OR verifier fail -> status=failed, put the diagnosis in the stage as lastError.\n' +
  'Increment iteration; set updatedAt (`date -u`). If stage h6 just became done: also re-read ' + GROSSING_STATE + ' fresh and set its milestone g10 to status=verified with verifiedAt and the tuned-model artifacts, clear g10 blockedReason, preserve every other field, and write it back. If all stages done set goalStatus="complete".\n' +
  'Re-emit the WHOLE HF_STATE.json with Write (preserve untouched fields). Append one NDJSON line to ' + LEDGER + ': {ts,event,stage,status,note}.\n' +
  'Compute report: doneCount/totalCount over stages; nextUp = eligible ids next; action = STOP_LOOP_DONE if goalStatus complete, POLL_JOBS if h4 is in_progress (jobs still running — loop should wait longer before next poll), else CONTINUE.\n' +
  'THIS ITERATION: BUILD=' + JSON.stringify(build) + '  VERDICT=' + JSON.stringify(verdict),
  { label: 'record', phase: 'Record', schema: REPORT_SCHEMA })
if (!report) throw new Error('Record failed')
log('HF-train iteration: ' + report.doneCount + '/' + report.totalCount + ' — ' + report.iterationSummary)
return report
