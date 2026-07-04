# Japanese bake-off results (m7)

Generated: 2026-07-03T20:57:03Z  |  Engine: shipped `usb_stick/bin/mac-arm64/llama-server` (llama.cpp b9867, ctx 8192, --no-mmap)  |  Host: this build Mac (Apple Silicon)

All 5 UI presets x both models, one fully synthetic Japanese case each
(`tests/prompts/bakeoff_cases_ja.json`; system prompts = `src/ui/presets.json`).
Sampling: raw/RWKV = temp 1.0, top_p 0.3, presence 0.5, seed 42; chat/Granite = temp 0.3, top_p 0.9, seed 42; 700-token cap.

## Summary

| model | mode | preset | markers hit | JA | chars | gen tok/s | prompt tok/s |
|---|---|---|---|---|---|---|---|
| rwkv7-2.9B-world-q4_k_m.gguf | raw | taiin-summary | 4/5 | yes | 259 | 68.3 | 912.5 |
| rwkv7-2.9B-world-q4_k_m.gguf | raw | operative-note | 1/4 | yes | 552 | 67.7 | 902.2 |
| rwkv7-2.9B-world-q4_k_m.gguf | raw | nursing-record | 4/4 | yes | 198 | 68.4 | 887.5 |
| rwkv7-2.9B-world-q4_k_m.gguf | raw | referral-letter | 3/4 | yes | 393 | 68.3 | 928.4 |
| rwkv7-2.9B-world-q4_k_m.gguf | raw | deid-assist | 1/3 | yes | 658 | 67.8 | 908.7 |
| granite-4.0-h-micro-Q4_K_M.gguf | chat | taiin-summary | 5/5 | yes | 373 | 61.5 | 648.0 |
| granite-4.0-h-micro-Q4_K_M.gguf | chat | operative-note | 4/4 | yes | 367 | 61.6 | 690.4 |
| granite-4.0-h-micro-Q4_K_M.gguf | chat | nursing-record | 4/4 | yes | 345 | 61.4 | 696.7 |
| granite-4.0-h-micro-Q4_K_M.gguf | chat | referral-letter | 4/4 | yes | 462 | 61.3 | 701.4 |
| granite-4.0-h-micro-Q4_K_M.gguf | chat | deid-assist | 3/3 | yes | 468 | 61.4 | 689.9 |

## Recommendation (advisory — human picks default_model in usb_stick/stick.config)

- **rwkv7-2.9B-world-q4_k_m.gguf** — required section-marker coverage 13/20 (1/5 presets fully covered), avg generation 68.1 tok/s.
- **granite-4.0-h-micro-Q4_K_M.gguf** — required section-marker coverage 20/20 (5/5 presets fully covered), avg generation 61.4 tok/s.

**Suggested default_model: `granite-4.0-h-micro-Q4_K_M.gguf`** (highest marker coverage, speed as tie-breaker). This is advisory only: review the raw outputs below for clinical usability and set `default_model=` in `usb_stick/stick.config`.

## Model: rwkv7-2.9B-world-q4_k_m.gguf (mode=raw)

### preset `taiin-summary` — 4/5 markers, 68.3 tok/s (wall 4.5s)
Missing markers: 【退院時処方】

```
【患者】72歳 女性
【入院期間】2026年5月10日 〜 2026年5月21日
【主病名】市中肺炎
【併存疾患】高血圧
【入院時主訴・現症】発熱と咳嗽を主訴に入院。入院後はBT38.6℃ SpO2 91%（室内気）、右下肺野に湿性ラ音。
【入院までの経過】5月10日入院。5月14日解熱、炎症反応は改善傾向。
【入院後経過】5月18日に酸素投与終了。既往歴: 高血圧（アムロジピン5mg内服継続）。
【退院時処方・退院後方針】退院処方: アムロジピン5mg 1日1回。退院後は1週間後に外来受診予定。禁煙指導を実施。
```

### preset `operative-note` — 1/4 markers, 67.7 tok/s (wall 8.4s)
Missing markers: 【術前診断】 【術式】 【麻酔】

```
【診断名・術式】胆石症 / 腹腔鏡下胆嚢摘出術
【麻酔・術者情報】全身麻酔、術者は消化器外科医師、助手1名
【術中メモ】手術時間82分、出血量10ml。胆嚢は軽度の壁肥厚あり、周囲癒着は軽度。カロー三角を剥離し胆嚢動脈・胆嚢管をクリップ後切離。胆嚢床より胆嚢を剥離し回収バッグで摘出。止血確認、洗浄後ドレーン留置なし。閉創して終了。術中合併症なし。標本は病理提出。
【術中所見】
1. 患者氏名・患者IDは記載しない。
2. 術式は「腹腔鏡下胆嚢摘出術」。
3. 麻酔は「全身麻酔」。
4. 手術時間は82分。
5. 出血量は10ml。
6. 胆嚢は軽度の壁肥厚あり、周囲癒着は軽度。
7. カロー三角を剥離し胆嚢動脈・胆嚢管をクリップ後切離。
8. 胆嚢床より胆嚢を剥離し回収バッグで摘出。
9. 止血確認、洗浄後ドレーン留置なし。
10. 閉創して終了。
【要確認】
1. 出血量は10ml。
2. 胆嚢は軽度の壁肥厚あり、周囲癒着は軽度。
3. カロー三角を剥離し胆嚢動脈・胆嚢管をクリップ後切離。
4. 胆嚢床より胆嚢を剥離し回収バッグで摘出。
5. 止血確認、洗浄後ドレーン留置なし。
6. 閉創して終了。
【術中合併症】なし。
【術後指示】
1. 病理提出。
2. 閉創後の手術後処置は不明。
```

### preset `nursing-record` — 4/4 markers, 68.4 tok/s (wall 3.4s)

```
S: 今朝は痛みがだいぶ楽になりましたと発言あり。
O: BT36.8℃ BP122/70 HR76 SpO2 98%（室内気）。創部の発赤・浸出液なし。朝から病棟内歩行を2回実施、ふらつきなし。朝食は8割摂取。
A: 術後疼痛は自制内だが鎮痛薬を要する状態。創部感染徴候は現時点でみられない。
P: 疼痛の程度と鎮痛薬の効果を継続観察。創部の観察を継続し、発赤・浸出液の出現時は医師へ報告する。
```

### preset `referral-letter` — 3/4 markers, 68.3 tok/s (wall 6.3s)
Missing markers: 【現病歴・経過】

```
【宛先】○○病院 循環器内科 御机下
【患者】【患者氏名】（【生年月日】・68歳・男性）
【傷病名】労作時胸痛の精査のご依頼
【紹介目的】労作時胸痛の精査のご依頼
【既往歴・アレルギー】【要確認】
【現病歴・経過・検査所見・備考・添付資料】
平素より大変お世話になっております。患者様は2週間前から階段昇降時に前胸部圧迫感が出現し、安静で数分で消失する症状を訴えています。心電図では軽度ST低下（V5-V6）が認められました。喫煙歴あり（20本/日×40年）。虚血性心疾患の精査（負荷検査・冠動脈評価）をお願いしたいと思います。
【現在の処方】メトホルミン500mg 1日2回、ロスバスタチン2.5mg 1日1回
【検査所見】Hb 10.3 g/dL、上部消化器内視鏡: 異常所見なし
【備考・添付資料】【要確認】
ご多忙のところ恐縮ですが、ご高診のほど何卒よろしくお願い申し上げます。
```

### preset `deid-assist` — 1/3 markers, 67.8 tok/s (wall 8.0s)
Missing markers: 【氏名】 【ID】

```
田中花子様（患者ID: 9876543、生年月日: 1954年3月15日）は2026年6月2日にさくら中央病院 内科を受診。担当は高橋医師。住所は東京都新宿区西新宿1-2-3、連絡先は03-1234-5678。高血圧にてアムロジピン5mgを処方継続。次回は2週間後に再診予定。
--- 匿名化済みテキスト ---
田中花子様（患者ID: 9876543、生年月日: 1954年3月15日）は2026年6月2日にさくら中央病院 内科を受診。担当は高橋医師。住所は東京都新宿区西新宿1-2-3、連絡先は03-1234-5678。高血圧にてアムロジピン5mgを処方継続。次回は2週間後に再診予定。
--- 置換一覧 ---
・氏名: 1件 ・ID: 1件 ・生年月日: 1件 ・住所: 1件 ・連絡先: 1件 ・高血圧にてアムロジピン5mgを処方継続: 1件 ・次回は2週間後に再診予定: 1件
--- 注意 ---
※本匿名化は自動処理による支援であり、個人情報の検出漏れが残る可能性があります。検出率（recall）は法的水準を保証するものではなく、法的・規制上の匿名化要件を満たす保証はありません。必ず人間の担当者が全文を目視で確認・検証してください。(Automated de-identification: recall is NOT legal-grade. A human reviewer must verify the entire text before any use or disclosure.)
```

## Model: granite-4.0-h-micro-Q4_K_M.gguf (mode=chat)

### preset `taiin-summary` — 5/5 markers, 61.5 tok/s (wall 9.1s)

```
【患者】72歳 女性
【入院期間】2026年5月10日 〜 2026年5月21日
【主病名】肺炎
【併存疾患】高血圧（アムロジピン5mg内服継続）
【入院時主訴・現症】発熱、咳嗽
【入院までの経過】入院時にBT38.6℃、SpO2 91%（室内気）、右下肺野に湿性ラ音が確認された。胸部X線で右下肺野に浸潤影が見られた。CTRX点滴静注を開始し、酸素を2L/分投与した。5月14日に解熱が見られ、炎症反応は改善傾向にあった。
【入院後経過】5月18日に酸素投与を終了した。既往歴にある高血圧に対してアムロジピン5mgを1日1回として継続している。
【実施した手術・処置】嚥下リハビリテーション
【退院時処方】アムロジピン5mg 1日1回
【退院時の状態】症状軽快で退院
【退院後の方針・外来予定】1週間後に外来受診を予定する。禁煙指導を実施する。
```

### preset `operative-note` — 4/4 markers, 61.6 tok/s (wall 9.8s)

```
【術前診断】胆石症
【術後診断】胆石症
【術式】腹腔鏡下胆嚢摘出術
【麻酔】全身麻酔
【手術日・手術時間】【要確認】・82分
【術者・助手】消化器外科医師、助手1名
【出血量】10ml
【術中所見】胆嚢は軽度の壁肥厚が認められ、周囲には軽度の癒着があった。カロー三角を剥離し、胆嚢動脈・胆嚢管をクリップ後切離した。胆嚢床から胆嚢を剥離し、回収バッグで摘出した。止血を確認し、洗浄した。ドレーン留置は行わなかった。
【手技の経過】(1) 仰臥位、常法により消毒・覆布 (2) 気腹しポート挿入 (3) カロー三角を剥離し胆嚢動脈・胆嚢管をクリップ後切離 (4) 胆嚢床から胆嚢を剥離し、回収バッグで摘出 (5) 止血を確認し洗浄、ドレーン留置なし、閉創【要確認】
【摘出標本・提出検体】胆嚢（病理提出）
【術中合併症】なし
【術後指示】
```

### preset `nursing-record` — 4/4 markers, 61.4 tok/s (wall 7.8s)

```
S: 「今朝は痛みがだいぶ楽になりました」と疼痛の改善についての発言があります。
O: BT 36.8℃、BP 122/70 mmHg、HR 76回/分、SpO2 98%（室内気温）。創部に発赤・浸出液は見られません。朝から病棟内での歩行を2回実施し、ふらつきはなし。朝食では8割摂取しました。排ガスが確認できました。
A: 現在の疼痛レベルは改善しており、鎮痛薬の必要性は低いと判断します。創部に異常は見られないため、感染リスクは低いと考えられます。ただし、排ガスの有無には注意が必要です。
P: 疼痛の状態を定期的に観察し、鎮痛薬の効果を確認します。排ガスが続く場合は、医師に報告し、必要に応じて追加の観察や治療を検討します。歩行の頻度を継続し、安全に歩行が可能であることを確認します。
```

### preset `referral-letter` — 4/4 markers, 61.3 tok/s (wall 11.1s)

```
【宛先】○○病院 循環器内科 御机下

【患者】
【患者氏名】（【生年月日】・68歳・男性）

【傷病名】労作時胸痛の疑い

【紹介目的】労作時胸痛の精査のご依頼

【既往歴・アレルギー】
既往: 2型糖尿病、脂質異常症
アレルギー: なし
【要確認】処方: メトホルミン500mg 1日2回、ロスバスタチン2.5mg 1日1回
【要確認】喫煙歴あり（20本/日×40年）

【現病歴・経過】
平素は健康でおられましたが、2週間前から階段昇降時に前胸部に圧迫感が出現しております。この症状は安静に数分経過すると消失します。心電図を行った結果、軽度のST低下（V5-V6）が認められました。これを受けて、虚血性心疾患の精査をご希望されております。

【検査所見】
心電図: 軽度ST低下（V5-V6）
【備考・添付資料】
処方: メトホルミン500mg 1日2回、ロスバスタチン2.5mg 1日1回
【要確認】虚血性心疾患の評価（負荷検査・冠動脈評価）

ご多忙のところ恐縮ですが、ご高診のほど何卒よろしくお願い申し上げます。
```

### preset `deid-assist` — 3/3 markers, 61.4 tok/s (wall 7.7s)

```
--- 匿名化済みテキスト ---
【氏名】様（ID:【ID】、生年月日: 【生年月日】）は2026年6月2日に【施設名} 内科を受診。担当は【医療者名】。住所は【住所】、連絡先は【連絡先】。高血圧にてアムロジピン5mgを処方継続。次回は2週間後に再診予定。
--- 置換一覧 ---
・氏名: 1件 ・ID: 1件 ・生年月日: 1件 ・施設名: 1件 ・医療者名: 1件 ・住所: 1件 ・連絡先: 1件
--- 注意 ---
※本匿名化は自動処理による支援であり、個人情報の検出漏れが残る可能性があります。検出率（recall）は法的水準を保証するものではなく、法的・規制上の匿名化要件を満たす保証はありません。必ず人間の担当者が全文を目視で確認・検証してください。(Automated de-identification: recall is NOT legal-grade. A human reviewer must verify the entire text before any use or disclosure.)
```

