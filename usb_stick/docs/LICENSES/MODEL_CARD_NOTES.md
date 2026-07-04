# Model Card Notes / モデルカード注記

Both bundled language models are released under the **Apache License 2.0**
(full text: [Apache-2.0.txt](Apache-2.0.txt)). The llama.cpp inference engine is
MIT-licensed (full text: [llama.cpp-b9867-LICENSE.txt](llama.cpp-b9867-LICENSE.txt)).
Usage disclaimer: [DISCLAIMER.md](DISCLAIMER.md).

同梱の2つの言語モデルはいずれも **Apache License 2.0** で提供されています。
推論エンジン llama.cpp は MIT ライセンスです。利用上の免責事項は
[DISCLAIMER.md](DISCLAIMER.md) を参照してください。

---

## Primary model: RWKV-7 World 2.9B (Q4_K_M GGUF)

| Field | Value |
|---|---|
| Architecture | RWKV-7 — non-Transformer, linear attention ("world" multilingual chat variant) |
| Source repo | Hugging Face: `Mungert/rwkv7-2.9B-world-GGUF` |
| File | `rwkv7-2.9B-world-q4_k_m.gguf` (Q4_K_M, ~1.88 GB) |
| sha256 | `d80eadb5a5db0689a6e3a6689128670530b30203c44404510f77f553368253e8` |
| License | Apache-2.0 |
| Languages | Multilingual incl. Japanese (World training corpus) |

Notes / 注記:

- General-purpose multilingual chat model. **Not trained, fine-tuned, or
  evaluated on medical tasks.** All medical framing comes from the preset
  prompts on this stick. / 汎用多言語モデルであり、**医療タスクでの学習・
  評価は行われていません**。医療文書の形式はスティック内のプリセット
  プロンプトによるものです。
- Q4_K_M quantization trades accuracy for size/speed; occasional wording errors
  and terminology slips are expected. / 4bit量子化により精度は一部低下します。
- May generate fluent but incorrect statements (hallucination). Presets instruct
  the model to mark unknowns as 【要確認】, but this is not guaranteed.
  流暢だが誤った記述（ハルシネーション）があり得ます。

## Fallback model: IBM Granite 4.0-h micro (Q4_K_M GGUF)

| Field | Value |
|---|---|
| Architecture | Granite hybrid — Mamba-2 / Transformer hybrid (non-standard attention) |
| Source repo | Hugging Face: `ibm-granite/granite-4.0-h-micro-GGUF` (official IBM repo) |
| File | `granite-4.0-h-micro-Q4_K_M.gguf` (Q4_K_M, ~1.94 GB) |
| sha256 | `bcc78b9b25450101d1ad90d4b9a264e1bac892f534dfb76066f4eec792fdf023` |
| License | Apache-2.0 |
| Languages | Multilingual incl. Japanese; strong instruction following |

Notes / 注記:

- Same caveats as above: no medical training or clinical evaluation; quantized;
  can hallucinate. / 上記と同じ注意（医療学習なし・量子化・誤生成あり得る）。

## De-identification caveat / 匿名化支援に関する重要な注意

The 匿名化支援 (De-identification Assist) preset performs **best-effort
masking only**. Small quantized models do **not** achieve the recall required
for legally reliable de-identification: identifiers can and will occasionally
slip through. Treat its output as a *first pass* that a human must verify
line-by-line before any text is considered de-identified.

「匿名化支援」プリセットは**ベストエフォートのマスキング**に過ぎません。
小型の量子化モデルでは、法的に十分な検出率（再現率）は達成できず、
識別子が残存し得ます。出力は必ず人間が一行ずつ確認してください。
