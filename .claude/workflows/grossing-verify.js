export const meta = {
  name: 'grossing-verify',
  description: 'Full adversarial re-validation of ALL verified milestones of the Sovereign Grossing Voice build (re-hash, live end-to-end smoke incl. the silence->zero-tokens safety test). Green run sets finalVerifyPassed; regressions demote milestones for grossing-build to repair.',
  whenToUse: 'Invoked by the /loop driver once every non-blocked milestone in /Users/osx/Documents/sovereign-grossing-voice/STATE.json is verified, and as a final paranoia pass after goal completion.',
  phases: [
    { title: 'Audit', detail: 'parallel independent verifier per verified milestone; full re-hash; live e2e + silence-safety smoke; UI self-containment' },
    { title: 'Record', detail: 'demote regressions to pending (attempts reset), or set finalVerifyPassed + goalStatus=complete (respecting blocked g10)' },
  ],
}

const ROOT = '/Users/osx/Documents/sovereign-grossing-voice'
const CORE = '/Users/osx/Documents/med_l_llm'
const STATE = ROOT + '/STATE.json'
const LEDGER = ROOT + '/ledger.ndjson'

const CONTEXT = [
  '=== SOVEREIGN GROSSING VOICE — VERIFY ===',
  'REPO ROOT: ' + ROOT + ' (STATE: ' + STATE + ', LEDGER: ' + LEDGER + '). Shared core submodule: ' + ROOT + '/core (source ' + CORE + ').',
  'The pipeline: push-to-talk + Silero VAD → whisper.cpp ASR (JA/EN) → ~3B LLM structuring (GBNF → CAP/ICCR synoptic JSON, unfilled → VERIFY) → secretary-verified transcript-beside-draft UI → auditgw hash-chain log, accession-bound. Offline, non-device.',
  'MANDATORY SAFETY INVARIANT: under push-to-talk, silence/pauses produce ZERO transcribed tokens (no fabricated findings). Re-test this live.',
  'checks/ holds one mechanical verify script per milestone (exit 0 = pass); DoD lists are in STATE.json.',
  'RULES: verifiers are READ-ONLY plus test-execution (checks/*.sh, shasum full re-hash, bash -n, whisper.cpp/llama.cpp on samples, the live e2e + silence smoke, git submodule status). NO Write/Edit/delete/download.',
  'g10 (RunPod) may legitimately be blocked (runpodConnectivity false) — a blocked g10 does NOT prevent finalVerifyPassed for the non-blocked scope; note it as blocked, not failed.',
  '=== END CONTEXT ===',
].join('\n')

const SCAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verified', 'notVerified', 'blocked', 'finalVerifyPassed', 'goalStatus'],
  properties: {
    verified: { type: 'array', items: {
      type: 'object', additionalProperties: false,
      required: ['id', 'title', 'definitionOfDone', 'checkScript', 'artifacts'],
      properties: {
        id: { type: 'string' }, title: { type: 'string' },
        definitionOfDone: { type: 'array', items: { type: 'string' } },
        checkScript: { type: ['string', 'null'] },
        artifacts: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'sha256', 'bytes'], properties: { path: { type: 'string' }, sha256: { type: 'string' }, bytes: { type: 'number' } } } },
      },
    } },
    notVerified: { type: 'array', items: { type: 'string' } },
    blocked: { type: 'array', items: { type: 'string' } },
    finalVerifyPassed: { type: 'boolean' }, goalStatus: { type: 'string' },
  },
}

const AUDIT_SCHEMA = {
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

const RESULT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['allGreen', 'regressed', 'summary', 'action'],
  properties: {
    allGreen: { type: 'boolean' }, regressed: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' }, action: { type: 'string', enum: ['STOP_LOOP', 'CONTINUE'] },
  },
}

phase('Audit')
const scan = await agent(CONTEXT + '\n\nRead ' + STATE + ' (read-only). Return every milestone with status "verified" (id, title, definitionOfDone, checkScript, artifacts), the ids NOT verified, the ids blocked, plus finalVerifyPassed and goalStatus.',
  { label: 'scan-state', phase: 'Audit', schema: SCAN_SCHEMA })

if (!scan) throw new Error('State scan failed')
if (scan.verified.length === 0) return { allGreen: false, regressed: [], summary: 'No verified milestones to audit yet — run grossing-build.', action: 'CONTINUE' }
if (scan.notVerified.length > scan.blocked.length) log('Note: ' + (scan.notVerified.length - scan.blocked.length) + ' milestones not yet verified (excluding blocked): ' + scan.notVerified.join(', '))

const audits = (await parallel(scan.verified.map(function (m) {
  return function () {
    return agent(CONTEXT + '\n\nYOU ARE AN INDEPENDENT AUDITOR for previously-verified milestone ' + m.id + ': ' + m.title + '\n' +
      'DEFINITION OF DONE (re-verify EVERY item from scratch, trust nothing):\n' +
      m.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
      'Recorded artifacts (FULLY re-hash each with shasum -a 256 and compare): ' + JSON.stringify(m.artifacts) + '\n' +
      (m.checkScript ? 'Execute ' + m.checkScript + ' and inspect its source: a rubber-stamp script is itself a FAIL.\n' : '') +
      ((m.id === 'g8' || m.id === 'g3') ? 'This milestone carries the SAFETY INVARIANT: RE-RUN the live silence->zero-transcribed-tokens test for real.\n' : '') +
      (m.id === 'g8' ? 'Also re-run the live end-to-end synthetic-audio smoke.\n' : '') +
      'Paste actual command output as evidence. Return per-check verdicts and overall pass/fail.',
      { label: 'audit:' + m.id, phase: 'Audit', schema: AUDIT_SCHEMA })
  }
}))).filter(Boolean)

phase('Record')
const result = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT - the ONLY agent allowed to write ' + STATE + ' and ' + LEDGER + '.\n' +
  'Audit results: ' + JSON.stringify(audits) + '\n' +
  'Not-yet-verified (untouched): ' + JSON.stringify(scan.notVerified) + '  Blocked: ' + JSON.stringify(scan.blocked) + '\n' +
  'Apply: each audit overall=fail -> demote that milestone to status="pending", attempts reset to 0 (a regression is new work), lastError=failureReason, verifiedAt=null; append an AUDIT_FAIL ledger line per demotion.\n' +
  'If ALL audits pass AND every not-verified milestone is blocked (i.e. only blocked work like g10 remains): set finalVerifyPassed=true; set goalStatus="complete" ONLY if there are zero blocked milestones too, otherwise leave goalStatus="building" and note that completion awaits the blocked items (RunPod). Append a ledger line.\n' +
  'Timestamps via `date -u`. Re-emit the WHOLE STATE.json with Write (preserve untouched fields). Update GOAL.md table.\n' +
  'Return: allGreen (all audits passed AND nothing left unverified except blocked), regressed (demoted ids), summary (one paragraph: what regressed + why, or the package summary — pipeline stages, models, synthetic-triple count, safety-test result, what remains blocked), action = STOP_LOOP if goalStatus complete OR only-blocked-remains, else CONTINUE.',
  { label: 'record', phase: 'Record', schema: RESULT_SCHEMA })

if (!result) throw new Error('Record agent failed')
log(result.allGreen ? 'FULL VERIFY GREEN: ' + result.summary : 'Regressions: ' + result.regressed.join(', ') + ' — ' + result.summary)
return result
