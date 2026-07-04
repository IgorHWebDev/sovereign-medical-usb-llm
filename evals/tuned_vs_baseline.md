# Tuned (base + smoke LoRA adapter) vs baseline - pipeline proof

Generated: 2026-07-03T23:17:07Z

- Model: mlx-community/granite-4.0-h-micro-4bit (MLX 4-bit weights of the stick
  default ibm-granite/granite-4.0-h-micro, arch `granitemoehybrid`)
- Adapter: `training/adapters/` (smoke QLoRA: rank 8, ~15 steps on 48 medqa_jp
  examples - see `training/logs/smoke_train.log`)
- Eval: 20 held-out medqa_jp items (taken from the END of the corpus; the
  train/valid splits come from the START, so the sets are disjoint), greedy
  decoding (temp=0), max 60 new tokens, answer letter extracted
  by regex.

**This is a pipeline proof only - no quality bar is claimed or required.**
A ~15-step adapter on 48 examples cannot and should not move real accuracy;
real gains need the hospital gold set + off-site GPU SFT, then m7 bake-off +
m9 validation re-runs (see `training/README_TRAINING.md`).

## Summary

| run | correct / 20 | accuracy |
|---|---|---|
| baseline (no adapter) | 7 / 20 | 0.35 |
| tuned (smoke adapter) | 4 / 20 | 0.20 |

## Per-item results

| sample_id | gold | baseline | tuned | baseline output (trunc) | tuned output (trunc) |
|---|---|---|---|---|---|
| train_10177 | D | B X | D OK | 正解はB. 不可避流産です。 | 正解はD. 部分モーラ妊娠です。 |
| train_10176 | C | A X | E X | 正解はA. 分岐鎖アルファケト酸脱水素酵素です。 | 正解はE. プロピオニル-CoAカルボキシラーゼです。 |
| train_10175 | B | B OK | E X | 正解はB. アセトアミノフェン. | 正解はE. サリチル酸塩です。 |
| train_10174 | B | B OK | B OK | 正解はB. 尿中微量アルブミン/クレアチニン比です。 | 正解はB. 尿中微量アルブミン/クレアチン比です。 |
| train_10173 | B | C X | E X | 正解はC. 低張性液を投与するです。 | 正解はE. 頭部CTを実施するです。 |
| train_10172 | D | C X | E X | 正解はC. 増加したFEF25-75。 | 正解はE. 減少した機能的残気量（FRC）。 |
| train_10171 | A | A OK | A OK | 正解はA. 低アルブミン血症です。 | 正解はA. 低アルブミン血症です。 |
| train_10170 | C | A X | E X | 正解はA. cAMP. 授乳中のミルク分泌を促進する主要なホルモンはプロスタグランジンE2（PGE2）であり、これはcAMP（ | 正解はE. リン脂質Aです。 |
| train_10169 | C | B X | E X | 正解はB. 冠動脈造影です。 | 正解はE. アルファフェトプロテインの血清測定です。 |
| train_10168 | D | C X | E X | 正解はC. 骨です。 | 正解はE. 脳です。 |
| train_10167 | E | B X | A X | 正解はB. 患者に診断を開示する。   医師は法律や倫理に基づいて患者に診断を開示する義務があります。患 | 正解はA. 患者に真実を知りたいかどうか尋ねるです。 |
| train_10166 | B | B OK | E X | 正解はB. ミエロペルオキシダーゼです。 | 正解はE. IV型コラーゲンです。 |
| train_10165 | A | C X | E X | 正解はC. メサラミン浣腸です。 | 正解はE. 大腸の一部の手術的切除です。 |
| train_10164 | C | C OK | E X | 正解はC. 鼻内投与のナロキソンです。 | 正解はE. 経口でのオレンジジュースです。 |
| train_10163 | A | C X | E X | 正解はC. 白血球性カストです。 | 正解はE. グルコース。 |
| train_10162 | B | B OK | D X | 正解はB. マクロファージ. これらの黄色い斑点は、心臓の動脈における炎症反応の結果として形成されるマクロ | 正解はD. T細胞です。 |
| train_10161 | D | A X | A X | 正解はA. アルブミン。アルブミンは血中で腎臓によって輸送されるため、糸球体濾過率が一定の条件下で排� | 正解はA. アルブミンです。 |
| train_10160 | B | C X | D X | 正解はC. 赤ちゃんの周りで誰もが喫煙しないようにする。   喫煙は突然死症候群（SIDS）のリスク | 正解はD. 赤ちゃんに柔らかい寝具や枕を使用するです。 |
| train_10159 | C | C OK | A X | 正解はC. 核受容体に結合する。 | 正解はA. 環状アデノシン一リン酸（cAMP）を増加させるです。 |
| train_10158 | E | C X | E OK | 正解はC. 腸間膜虚血です。 | 正解はE. 敗血症です。 |
