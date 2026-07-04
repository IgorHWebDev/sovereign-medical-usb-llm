export const meta = {
  name: 'usb-verify',
  description: 'Full adversarial re-validation of ALL verified milestones of the med-USB build (full re-hash, live smoke). Green run sets finalVerifyPassed; any regression demotes the milestone so usb-build repairs it.',
  whenToUse: 'Invoked by the /loop driver once every milestone in /Users/osx/Documents/med_l_llm/STATE.json is verified, and as a final paranoia pass after goal completion.',
  phases: [
    { title: 'Audit', detail: 'parallel independent verifier per verified milestone; full sha256 re-hash; live macOS smoke; manifest check' },
    { title: 'Record', detail: 'demote regressed milestones to pending (attempts reset), or set finalVerifyPassed + goalStatus=complete' },
  ],
}

const ROOT = '/Users/osx/Documents/med_l_llm'
const STATE = ROOT + '/STATE.json'
const LEDGER = ROOT + '/ledger.ndjson'

const CONTEXT = [
  '=== MED-USB VERIFY CONTEXT ===',
  'REPO ROOT: ' + ROOT + ' (STATE: ' + STATE + ', LEDGER: ' + LEDGER + ')',
  'The usb_stick/ tree is the shippable disk-on-key package: llama.cpp binaries (win-x64 + mac-arm64), non-Transformer GGUF models, auditgw Go gateway (hash-chain audit log), single-file offline web UI, dual launchers, bilingual docs, MANIFEST.sha256.',
  'checks/ holds one mechanical verify script per milestone (exit 0 = pass); DoD lists live in STATE.json.',
  'RULES: verifiers are READ-ONLY plus test-execution (may run checks/*.sh, shasum full re-hash, bash -n, file, and the live smoke incl. starting/stopping local 127.0.0.1 test servers). NO Write/Edit/delete/download.',
  '=== END CONTEXT ===',
].join('\n')

const SCAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['verified', 'notVerified', 'finalVerifyPassed', 'goalStatus'],
  properties: {
    verified: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'title', 'definitionOfDone', 'checkScript', 'artifacts'],
        properties: {
          id: { type: 'string' }, title: { type: 'string' },
          definitionOfDone: { type: 'array', items: { type: 'string' } },
          checkScript: { type: ['string', 'null'] },
          artifacts: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['path', 'sha256', 'bytes'], properties: { path: { type: 'string' }, sha256: { type: 'string' }, bytes: { type: 'number' } } } },
        },
      },
    },
    notVerified: { type: 'array', items: { type: 'string' } },
    finalVerifyPassed: { type: 'boolean' },
    goalStatus: { type: 'string' },
  },
}

const AUDIT_SCHEMA = {
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

const RESULT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['allGreen', 'regressed', 'summary', 'action'],
  properties: {
    allGreen: { type: 'boolean' },
    regressed: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    action: { type: 'string', enum: ['STOP_LOOP', 'CONTINUE'] },
  },
}

phase('Audit')
const scan = await agent(CONTEXT + '\n\nRead ' + STATE + ' (read-only). Return every milestone with status "verified" (id, title, definitionOfDone, checkScript, artifacts), the ids of milestones NOT verified, plus finalVerifyPassed and goalStatus.',
  { label: 'scan-state', phase: 'Audit', schema: SCAN_SCHEMA })

if (!scan) throw new Error('State scan failed')
if (scan.verified.length === 0) {
  return { allGreen: false, regressed: [], summary: 'No verified milestones to audit yet - run usb-build instead.', action: 'CONTINUE' }
}
if (scan.notVerified.length > 0) {
  log('Note: auditing ' + scan.verified.length + ' verified milestones; ' + scan.notVerified.length + ' not yet verified: ' + scan.notVerified.join(', '))
}

const audits = (await parallel(scan.verified.map(function (m) {
  return function () {
    return agent(CONTEXT + '\n\nYOU ARE AN INDEPENDENT AUDITOR for previously-verified milestone ' + m.id + ': ' + m.title + '\n' +
      'DEFINITION OF DONE (re-verify EVERY item from scratch, trust nothing):\n' +
      m.definitionOfDone.map(function (d, i) { return (i + 1) + '. ' + d }).join('\n') + '\n' +
      'Recorded artifacts (FULLY re-hash each with shasum -a 256 and compare - this audit does full re-hash, not size checks): ' + JSON.stringify(m.artifacts) + '\n' +
      (m.checkScript ? 'Execute ' + m.checkScript + ' and also inspect its source: a script that does not genuinely test the DoD is itself a FAIL.\n' : '') +
      (m.id === 'm7' ? 'This is the smoke-test milestone: RE-RUN the live macOS smoke (checks/smoke_mac.sh) for real, do not just check the file exists.\n' : '') +
      'Paste actual command output snippets as evidence. Return per-check verdicts and overall pass/fail.',
      { label: 'audit:' + m.id, phase: 'Audit', schema: AUDIT_SCHEMA })
  }
}))).filter(Boolean)

phase('Record')
const result = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT - the ONLY agent allowed to write ' + STATE + ' and ' + LEDGER + '.\n' +
  'Audit results: ' + JSON.stringify(audits) + '\n' +
  'Milestones not yet verified (untouched): ' + JSON.stringify(scan.notVerified) + '\n' +
  'Apply: for each audit with overall=fail -> demote that milestone to status="pending" with attempts reset to 0 (a regression is new work, not a retry), lastError = failureReason, verifiedAt = null; append an AUDIT_FAIL ledger line per demotion.\n' +
  'If ALL audits pass AND there are zero not-verified milestones: set finalVerifyPassed=true and goalStatus="complete", append a GOAL_COMPLETE ledger line, update GOAL.md.\n' +
  'Timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ`. Re-emit the WHOLE STATE.json with Write, preserving untouched fields exactly. Update the GOAL.md milestone table.\n' +
  'Return: allGreen (all audits passed AND nothing left unverified), regressed (demoted ids), summary (one paragraph incl. what regressed and why, or the final package summary: models, sizes, tok/s from the smoke, stick contents), action = STOP_LOOP if goalStatus is now complete, else CONTINUE.',
  { label: 'record', phase: 'Record', schema: RESULT_SCHEMA })

if (!result) throw new Error('Record agent failed')
log(result.allGreen ? 'FULL VERIFY GREEN: ' + result.summary : 'Regressions: ' + result.regressed.join(', ') + ' - ' + result.summary)
return result
