# Small-Model Accuracy — Final Verdict

*Synthesis of the accuracy-research campaign (11 deep-research iterations; see `ACCURACY_PLAYBOOK.md` for the cited evidence behind each point, `RESEARCH_STATE.json` for the knowledge base, `research_ledger.ndjson` for the audit trail).*

## Verdict: **CONDITIONAL-GO** (confidence: medium)

A ~3B model **can** be made accurate enough for the product — but only for a specific slice of the use cases, and only with a specific pipeline. The evidence is consistent and was stable across every iteration. The one thing literature cannot settle is the final number on *our* model and *our* data; that is an experiment, not a research question (below).

## The core finding: it's about TASK TYPE, not size

Every iteration reinforced one split:

- **Extraction / discriminative tasks — GO.** De-identification, NER, template-filling, structured classification. After light SFT a sub-3B model **matches or beats GPT-4o** here: NCVC-slm-1 (1.2B) went NER 0.00→0.90 and classification κ 0.01→0.98; a distilled 184M de-id model hit 0.89/0.88 precision/recall on CPU. This is the strongest, best-evidenced ground.
- **Documentation drafting — CONDITIONAL GO.** Discharge summaries, op-notes, referrals. Viable *as advisory drafts* with a verifier + human sign-off, benchmarked as non-inferior to the (imperfect) human baseline. Never autonomous.
- **Knowledge-reasoning / autonomous coding — NO-GO at 3B.** ICD/DPC coding is unacceptable out-of-box at *any* size (GPT-4 κ≈0.01 vs a certified coder), SFT collapses on real multi-condition notes (~69%), and RAG caps ~26% absolute even at 7–9B. Ship coding as *suggestion-only*, never a committed code.

## The pipeline that gets there (the "how")

1. **Model:** Granite-4.0-H-Micro (Mamba-*hybrid*), not pure RWKV. Confirmed three times — hybrids beat same-size Transformers (+2.65 avg) while pure SSMs lag ~15pt on in-context recall, which is why Granite won your bake-off.
2. **Fine-tune with QLoRA** on a small de-identified gold set. Uplift saturates at only **~200–1,000 examples** for extraction (sweet spot ~6,500); QLoRA is *not* the binding constraint (~15–30% uplift cost at most). MedGemma-4B kept its +6.8pp gain **under Q4 GGUF** — your exact quantized config.
3. **Do NOT lean on RAG.** It's net-negative below 7B and unstudied on RWKV/Mamba; use SFT for extraction instead. If retrieval is unavoidable, chunk-and-summarize flipped −5.7%→+3.6%.
4. **Add a conformal verifier** (CARE-style): flags 8–24% of outputs, catches 83–95% of hallucinations → the human reviews the flagged fraction. This is what makes a small model safe.
5. **Human confirms every output** (the non-device posture) — measure accuracy on the *post-confirmation* text.

## The eval that proves it (the make-or-break experiment)

Literature brackets but cannot answer the decisive question: **no ~3B model of any architecture has ever been benchmarked on Japanese clinical documentation.** You would be first. Run this in the pilot:

- **Model arms:** Granite-4.0-H-Micro Q4 — out-of-box vs QLoRA-fine-tuned; RWKV-7 as secondary arm.
- **Data:** a de-identified hospital gold set — start ~500–1,000 examples per document type (enough per the saturation curve).
- **Metrics:**
  - *Extraction/de-id:* precision/recall/F1 vs gold spans (target: beat the untuned baseline decisively; de-id recall toward legal-grade with the NER+regex hybrid).
  - *Documentation:* MedFactEval physician key-fact gold set + PDSQI-9 human rubric + AHRQ 0–7 harm grading, measured on post-confirmation output.
- **Success bar:** a **pre-registered non-inferiority test (TOST)** against the human baseline (1.82 ± 1.94 errors/summary), margin ~≤0.9 extra errors (loose) / ~0.48 aggregate-harm gap (strict), error budget aimed at omission.
- **Go/no-go:** GO if the fine-tuned 3B is non-inferior on documentation *and* beats baseline on extraction with the verifier flagging < ~25% for review. Otherwise fall back to the 7–8B tier on a dedicated workstation (the T1 escalation model) for the hard cases.

## Why "conditional," not "go"

The whole chain is evidenced on **Transformers on GPUs, in English/German**. The residual unknowns are all empirical and all about *our* stack specifically: (a) our RWKV/Mamba 4-bit-on-CPU number on Japanese text; (b) encounter-level generation error rate on real notes; (c) RAG behavior on a state-space model. None is a research gap — each is one run of the experiment above. That is exactly what the Phase-0 pilot is for.

## One-line answer

**Yes, a ~3B model can be accurate enough — for de-identification and human-confirmed documentation drafting, using a fine-tuned Granite hybrid + a conformal verifier, proven by a non-inferiority eval against the human baseline. Autonomous coding is out of reach at this size; keep it suggestion-only or escalate to a larger model.**
