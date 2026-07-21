export const meta = {
  name: 'accuracy-research',
  description: 'Research campaign: run deep-research over the open questions blocking an accurate ~3B small-model medical documentation product, accumulate verified findings into an evidence-backed accuracy playbook, and decide when the evidence is sufficient.',
  whenToUse: 'Invoked by the /loop driver, one research question per iteration, until the accuracy playbook can confidently answer "can a small non-Transformer model be made accurate enough, and how".',
  phases: [
    { title: 'Select', detail: 'bootstrap RESEARCH_STATE.json; pick the next open research question, or run the completeness critic to add questions or declare done' },
    { title: 'Research', detail: 'run the deep-research workflow on the selected question (fan-out → verify → synthesize)' },
    { title: 'Integrate', detail: 'merge cited findings into the knowledge base, extract new gaps, update the accuracy playbook' },
    { title: 'Record', detail: 'single-writer update of RESEARCH_STATE.json + ledger + playbook; decide CONTINUE / STOP' },
  ],
}

const ROOT = '/Users/osx/Documents/med_l_llm'
const STATE = ROOT + '/RESEARCH_STATE.json'
const LEDGER = ROOT + '/research_ledger.ndjson'
const PLAYBOOK = ROOT + '/ACCURACY_PLAYBOOK.md'
const MAX_QUESTIONS = 16   // hard cap so the completeness critic can't loop forever
const FORCE_QUESTION = (args && args.question) || null

const PRODUCT = 'A fully-offline medical documentation copilot on an encrypted USB stick for Japanese hospitals: a SMALL ~3B NON-TRANSFORMER model (RWKV-7 / Mamba-hybrid, GGUF 4-bit) served by llama.cpp, advisory + human-confirmed (non-device). The known make-or-break risk: is a ~3B model ACCURATE ENOUGH for clinical documentation (discharge summaries, op-notes, referrals), de-identification, and ICD/DPC coding — and if not out-of-the-box, exactly how do we close the gap (fine-tuning, RAG, distillation, quantization choices, structured decoding, verifiers, human-in-loop error budgets)? Every prior sovereign validation used 8B-70B models; no evidence yet validates ~3B on CPU.'

const INITIAL_STATE = {
  goal: 'Assemble an evidence-backed "accuracy playbook": determine whether — and precisely how — a ~3B non-Transformer model can be made accurate enough for advisory Japanese clinical-documentation, de-identification, and coding, with concrete techniques, expected quantitative gains, an eval protocol a hospital would accept, and a go/no-go read on the small-model thesis.',
  goalStatus: 'researching',
  iteration: 0,
  maxIterations: 14,
  confidenceInGoal: 'low',
  questions: [
    { id: 'q1', priority: 1, status: 'pending', question: 'What accuracy do existing SMALL (1.5B-8B) medical and Japanese-medical LLMs actually achieve on documentation/QA benchmarks (IgakuQA, JMedBench, JMMLU-medical, MedQA-JP)? Is there a measurable quality floor by parameter count, and where does ~3B land?' },
    { id: 'q2', priority: 1, status: 'pending', question: 'Quantitatively, how much does domain fine-tuning (SFT / LoRA / QLoRA) lift a small (~3B) base model on Japanese clinical documentation and coding tasks? Best recipes, data volume needed, and realistic accuracy deltas.' },
    { id: 'q3', priority: 1, status: 'pending', question: 'Can retrieval-augmented generation (RAG) let a ~3B model match a 70B model on clinical documentation, coding, and guideline-grounded tasks? Evidence of small-model+RAG closing the gap, and best practices for local/offline RAG.' },
    { id: 'q4', priority: 2, status: 'pending', question: 'Knowledge distillation from a large teacher (e.g., a 72B Japanese-medical model like Preferred-MedLLM) into a ~3B student for clinical text: techniques (sequence-level / logit / rationale distillation) and measured accuracy gains at the 3B scale.' },
    { id: 'q5', priority: 2, status: 'pending', question: 'How much accuracy is lost quantizing a ~3B model to 4-bit GGUF (Q4_K_M) for CPU inference, and how to minimize it (QAT, importance/imatrix quantization, higher-bit critical layers)? Evidence on quantization degradation for small models on domain tasks.' },
    { id: 'q6', priority: 2, status: 'pending', question: 'Do structured / constrained generation (grammars, JSON schema, templated slots) and task decomposition materially raise the reliability and factual accuracy of SMALL models on templated clinical documents? Evidence and methods usable with llama.cpp.' },
    { id: 'q7', priority: 1, status: 'pending', question: 'What is a rigorous, hospital-acceptable EVAL protocol to PROVE clinical-documentation accuracy of a drafting tool — metrics (factuality, hallucination/omission rate, coding accuracy), gold-set design, human evaluation, non-inferiority framing — and what error rates have peer-reviewed offline/local systems reported?' },
    { id: 'q8', priority: 3, status: 'pending', question: 'Verifier / self-consistency / small-ensemble and guardrail methods to catch a small model\'s errors, and how to design an acceptable residual-error budget for an ADVISORY human-signed documentation tool (what error rate is tolerable given a clinician confirms every output).' },
    { id: 'q9', priority: 2, status: 'pending', question: 'Non-Transformer specific: how does fine-tuning QUALITY and downstream task accuracy of RWKV-7 / Mamba-hybrid models at small scale (~3B) compare to Transformers of the same size on domain/instruction and long-document tasks? Any known weaknesses (retrieval, exact recall) relevant to clinical documentation.' },
    { id: 'q10', priority: 3, status: 'pending', question: 'For the de-identification use case specifically, what recall/precision can SMALL local models (with dictionary/regex hybrid guards) achieve on clinical PII in Japanese, and what architecture (NER + rules + LLM) reaches legal-grade recall offline?' },
  ],
  knowledge: [],          // accumulated {questionId, keyFindings:[...], sources:[...], confidence}
  openGaps: [],           // critic/deep-research-surfaced follow-ups not yet queued
  updatedAt: null,
}

const CONTEXT = [
  '=== ACCURACY-RESEARCH CAMPAIGN ===',
  'PRODUCT & RISK: ' + PRODUCT,
  'GOAL: ' + INITIAL_STATE.goal,
  'REPO: ' + ROOT + ' (STATE: ' + STATE + ', LEDGER: ' + LEDGER + ', PLAYBOOK: ' + PLAYBOOK + ')',
  'PRIOR CONTEXT (already established, do not re-research): the competitive landscape confirms the small-offline white-space is open; the SINGLE biggest open risk is small-model accuracy. Baselines measured: untuned Granite-3B ~40%, RWKV-2.9B ~35% on a JMMLU-medical subset (random 25%).',
  'DISCIPLINE: only the Record agent writes STATE/ledger/playbook. Findings must be cited (carried from deep-research). Prefer quantitative, peer-reviewed evidence; flag thin evidence honestly.',
  '=== END CONTEXT ===',
].join('\n')

const SELECT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['bootstrapped', 'goalComplete', 'stopped', 'stopReason', 'iteration', 'researchedCount', 'pendingCount', 'selectedQuestion', 'proposedNewQuestions', 'summary'],
  properties: {
    bootstrapped: { type: 'boolean' },
    goalComplete: { type: 'boolean' },
    stopped: { type: 'boolean' },
    stopReason: { type: 'string' },
    iteration: { type: 'number' },
    researchedCount: { type: 'number' },
    pendingCount: { type: 'number' },
    selectedQuestion: {
      type: ['object', 'null'], additionalProperties: false,
      required: ['id', 'question', 'rationale'],
      properties: { id: { type: 'string' }, question: { type: 'string' }, rationale: { type: 'string' } },
    },
    proposedNewQuestions: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'question', 'priority'],
        properties: { id: { type: 'string' }, question: { type: 'string' }, priority: { type: 'number' } },
      },
    },
    summary: { type: 'string' },
  },
}

const INTEGRATE_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['questionId', 'answered', 'keyFindings', 'newGaps', 'playbookSection', 'confidenceInGoal', 'goVerdict', 'notes'],
  properties: {
    questionId: { type: 'string' },
    answered: { type: 'boolean' },
    keyFindings: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['finding', 'confidence', 'implication', 'sources'],
        properties: {
          finding: { type: 'string' },
          confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
          implication: { type: 'string' },
          sources: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    newGaps: {
      type: 'array', items: {
        type: 'object', additionalProperties: false,
        required: ['question', 'priority'],
        properties: { question: { type: 'string' }, priority: { type: 'number' } },
      },
    },
    playbookSection: { type: 'string' },
    confidenceInGoal: { type: 'string', enum: ['low', 'medium', 'high'] },
    goVerdict: { type: 'string', enum: ['go', 'conditional-go', 'no-go', 'undetermined'] },
    notes: { type: 'string' },
  },
}

const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['researchedCount', 'totalQuestions', 'iterationSummary', 'confidenceInGoal', 'goVerdict', 'nextQuestion', 'action'],
  properties: {
    researchedCount: { type: 'number' },
    totalQuestions: { type: 'number' },
    iterationSummary: { type: 'string' },
    confidenceInGoal: { type: 'string' },
    goVerdict: { type: 'string' },
    nextQuestion: { type: 'string' },
    action: { type: 'string', enum: ['CONTINUE', 'STOP_LOOP_DONE', 'STOP_LOOP'] },
  },
}

// ---------- SELECT ----------
phase('Select')
const sel = await agent(CONTEXT + '\n\nYOU ARE THE SELECT AGENT for the accuracy-research campaign.\n' +
  '1. If ' + STATE + ' does NOT exist: create it EXACTLY from this INITIAL_STATE JSON (via Write), and also write ' + PLAYBOOK + ' as a stub titled "# Small-Model Accuracy Playbook" with a one-line goal and an empty findings section. Set bootstrapped=true.\n' +
  'INITIAL_STATE:\n' + JSON.stringify(INITIAL_STATE, null, 2) + '\n' +
  '2. Read ' + STATE + '. goalComplete = (goalStatus === "complete").\n' +
  (FORCE_QUESTION ? '   THE HUMAN FORCED a question: research this verbatim this iteration → "' + FORCE_QUESTION + '" (assign it a fresh id; include as selectedQuestion). \n' : '') +
  '3. If not forced: researchedCount = questions with status "researched"; pendingCount = status "pending". If iteration >= maxIterations, set stopped=true, stopReason="iteration cap reached", selectedQuestion=null.\n' +
  '4. Otherwise pick the highest-priority (lowest priority number, then lowest id) PENDING question as selectedQuestion.\n' +
  '5. If NO pending questions remain and not complete: act as COMPLETENESS CRITIC. Judge whether the accumulated knowledge answers the GOAL (a concrete accuracy plan with quantitative evidence, eval protocol, and a go/no-go read). If YES → goalComplete=true, selectedQuestion=null. If NO → propose up to 3 sharply-targeted NEW questions (proposedNewQuestions, priority 1-3, ids qN continuing the sequence, but never exceed ' + MAX_QUESTIONS + ' total) filling the biggest gaps, and set selectedQuestion to the first proposed one so it gets researched this iteration.\n' +
  'You may ONLY write files during step-1 bootstrap; otherwise read-only. Return per schema.',
  { label: 'select', phase: 'Select', schema: SELECT_SCHEMA })

if (!sel) throw new Error('Select agent failed')
log('Select: ' + sel.summary)

if (sel.goalComplete) return { action: 'STOP_LOOP_DONE', summary: sel.summary, researchedCount: sel.researchedCount }
if (sel.stopped) return { action: 'STOP_LOOP', stopReason: sel.stopReason, summary: sel.summary }
if (!sel.selectedQuestion) return { action: 'STOP_LOOP', stopReason: 'no question selected', summary: sel.summary }

const q = sel.selectedQuestion
log('Researching ' + q.id + ': ' + q.question)

// ---------- RESEARCH (nested deep-research workflow) ----------
phase('Research')
const researchQuery =
  'Research question (for a specific product): ' + q.question + '\n\n' +
  'PRODUCT CONTEXT (for relevance — tailor findings to this): ' + PRODUCT + '\n\n' +
  'Prioritise QUANTITATIVE, peer-reviewed or primary-source evidence (benchmark numbers, accuracy deltas, error rates). Explicitly compare small (~3B) vs larger models where possible. Flag where evidence is thin or extrapolated. Deliver cited findings with confidence levels.'

let research
try {
  research = await workflow('deep-research', researchQuery)
} catch (e) {
  research = { error: String(e), question: q.question, findings: [], summary: 'deep-research failed: ' + String(e), openQuestions: [], sources: [] }
}
log('deep-research returned ' + ((research && research.findings && research.findings.length) || 0) + ' findings for ' + q.id)

// ---------- INTEGRATE ----------
phase('Integrate')
const integ = await agent(CONTEXT + '\n\nYOU ARE THE INTEGRATE AGENT. A deep-research run just completed for question ' + q.id + ': "' + q.question + '".\n' +
  'DEEP-RESEARCH RESULT (verified, cited):\n' + JSON.stringify(research).slice(0, 24000) + '\n\n' +
  'Do the following (read-only; do NOT write STATE/playbook — the Record agent will persist your output):\n' +
  '1. Extract the keyFindings that bear on the GOAL: for each, a crisp finding, confidence (low/medium/high), the IMPLICATION for our ~3B product, and its source URLs. Convert vague claims into decision-relevant statements (e.g. "SFT lifts a 3B model by X points" not "fine-tuning helps").\n' +
  '2. answered = did this materially answer the question? \n' +
  '3. newGaps = any sharper follow-up questions this raised (from the deep-research openQuestions or your own judgement) that the campaign should pursue.\n' +
  '4. playbookSection = a clean Markdown section (## heading = the topic) summarising what we now know for the accuracy playbook, with inline source mentions and a bolded takeaway line. This will be APPENDED to ' + PLAYBOOK + '.\n' +
  '5. confidenceInGoal = your updated confidence that the overall GOAL is being met (low/medium/high), and goVerdict = your current read on the small-model thesis (go / conditional-go / no-go / undetermined) with the reason in notes.\n' +
  'Be rigorous and honest; do not overclaim from thin evidence.',
  { label: 'integrate:' + q.id, phase: 'Integrate', schema: INTEGRATE_SCHEMA })

if (!integ) throw new Error('Integrate agent failed')
log('Integrate: goVerdict=' + integ.goVerdict + ' confidence=' + integ.confidenceInGoal + ' newGaps=' + integ.newGaps.length)

// ---------- RECORD ----------
phase('Record')
const report = await agent(CONTEXT + '\n\nYOU ARE THE RECORD AGENT — the ONLY writer of ' + STATE + ', ' + LEDGER + ', and ' + PLAYBOOK + '.\n' +
  'Read current ' + STATE + '. Apply:\n' +
  '- Mark question ' + q.id + ' (or the forced question, adding it if new) status="researched"; attach integ.keyFindings + representative source URLs into knowledge[] under that id.\n' +
  '- Append proposedNewQuestions (from Select) AND integ.newGaps as NEW pending questions with continuing ids, deduping semantically and NEVER exceeding ' + MAX_QUESTIONS + ' total questions (drop lowest-priority extras).\n' +
  '- Set confidenceInGoal = integ.confidenceInGoal. Increment iteration. Set updatedAt via `date -u +%Y-%m-%dT%H:%M:%SZ`.\n' +
  '- If integ.confidenceInGoal === "high" AND no pending questions remain, OR iteration >= maxIterations, set goalStatus="complete".\n' +
  '- Re-emit the WHOLE STATE.json with Write (preserve untouched fields). APPEND integ.playbookSection to ' + PLAYBOOK + ' (never overwrite). Append one NDJSON line to ' + LEDGER + ': {ts, event:"RESEARCHED", question:"' + q.id + '", confidence, goVerdict, findings:<count>, newQuestions:<count>}.\n' +
  'Then decide action: STOP_LOOP_DONE if goalStatus now complete; STOP_LOOP if stuck (no pending + not complete); else CONTINUE. nextQuestion = the id/text of the next pending question (or "—").\n' +
  'INTEGRATE OUTPUT: ' + JSON.stringify(integ).slice(0, 20000) + '\n' +
  'SELECT PROPOSED: ' + JSON.stringify(sel.proposedNewQuestions),
  { label: 'record:' + q.id, phase: 'Record', schema: REPORT_SCHEMA })

if (!report) throw new Error('Record agent failed — STATE may not reflect this iteration')
log('Iteration done: ' + report.researchedCount + '/' + report.totalQuestions + ' researched · verdict=' + report.goVerdict + ' · ' + report.iterationSummary)
return report
