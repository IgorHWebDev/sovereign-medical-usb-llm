# Windows Validation Checklist / Windows動作検証チェックリスト

Manual test procedure for the **first run of this stick on a real hospital
Windows PC**. Perform once per PC model (or per policy change), with the IT
department informed. Do NOT use admin rights at any point — if a step seems to
require them, the correct outcome is *record and escalate*, not bypass.

実際の病院Windows PCで**初めて**本スティックを使用する際の手動検証手順です。
PC機種ごと（またはポリシー変更ごと）に1回、情報システム部門へ連絡のうえ実施
してください。全手順で管理者権限は使用しません。管理者権限が必要に見える場合は、
回避せず「記録して報告」が正しい対応です。

Tester / 実施者: ______________  Date / 日付: ______________
PC asset ID / PC管理番号: ______________  Windows version: ______________
RAM: ______ GB   Stick ID / スティック管理番号: ______________

## A. Preconditions / 事前確認

1. Confirm the PC is Windows 10 or 11, **64-bit x64** (Settings → System → About).
   PCがWindows 10/11の64ビット(x64)であることを確認する。
2. Confirm at least **8 GB RAM** (same screen). Below 8 GB: continue, but expect
   slowness and note it. / メモリが8GB以上あることを確認（8GB未満でも続行可、低速を記録）。
3. Confirm you are logged in as a **standard (non-admin) user**.
   一般ユーザー（非管理者）でログインしていることを確認する。
4. Sign the stick out on the custody register
   ([CUSTODY_REGISTER_TEMPLATE.md](CUSTODY_REGISTER_TEMPLATE.md)).
   持ち出し管理台帳に記入する。
5. If possible, disconnect the PC from the network (unplug LAN / disable Wi-Fi)
   for the duration of the test — the tool must work identically.
   可能ならテスト中はLANを抜く／Wi-Fiを無効化する（オフラインでも同一動作のはず）。

## B. Launch & SmartScreen / 起動とSmartScreen

6. Insert the stick; unlock it on its hardware keypad if it is an encrypted
   drive. Open it in Explorer and confirm `START_WINDOWS.bat`, `bin\win-x64\`,
   `models\`, `ui\`, `docs\` are present.
   スティックを挿入（暗号化ドライブは本体キーパッドで解錠）し、上記ファイル・
   フォルダの存在を確認する。
7. Double-click `START_WINDOWS.bat`.
8. **SmartScreen guidance / SmartScreen対応**: if a blue dialog
   "Windows protected your PC" (「WindowsによってPCが保護されました」) appears,
   click **More info (詳細情報) → Run anyway (実行)**. Record that it appeared.
   This is Mark-of-the-Web behavior for removable media and is expected.
9. If instead the script is **blocked entirely** (AppLocker / Software
   Restriction / group policy message, or the window flashes and closes),
   **stop here**: record the exact message, mark FAIL for this PC, and escalate
   to IT. Do not attempt any admin-level workaround.
   完全にブロックされた場合はここで中止し、メッセージを記録してIT部門へ報告する。
10. If antivirus/EDR quarantines or deletes any file on the stick, record the
    product name and detection name, mark FAIL, escalate to IT (allow-listing
    is an IT action). / ウイルス対策ソフトによる隔離・削除が発生した場合は記録
    のうえIT部門へ（許可リスト登録はIT側の作業）。

## C. Startup behaviour / 起動動作

11. In the console window, confirm: a RAM note (if < 8 GB), port selection
    messages, and no ERROR lines. / コンソールにERROR表示がないことを確認。
12. Wait for model load (up to ~2 minutes on first start from USB). Confirm the
    default browser opens automatically at `http://127.0.0.1:8180/` (or another
    port in 8180–8199). / ブラウザが自動的に開くことを確認する。
13. If the browser does not open, open one manually and try
    `http://127.0.0.1:8180/` … `8199`. Record which port worked.

## D. Offline & loopback verification / オフライン・ループバック確認

14. With the network still disconnected (step 5), confirm the UI loads and works.
    ネットワーク切断状態のままUIが動作することを確認する。
15. Open Command Prompt and run: `netstat -an | findstr "818"` and
    `netstat -an | findstr "808"`. Confirm every LISTENING line for these ports
    shows **127.0.0.1** (not 0.0.0.0). Record the output.
    LISTENING行がすべて 127.0.0.1 であること（0.0.0.0 でないこと）を確認する。

## E. Functional test / 機能テスト

16. Enter an operator ID when the UI asks for one (use your staff ID — it is
    written to the audit log). / 操作者IDを入力する（監査ログに記録されます）。
17. Select the 退院サマリー (Discharge Summary) preset. Enter the sample:
    `78歳 男性 誤嚥性肺炎 4月1日入院 抗菌薬で改善 4月10日退院 嚥下リハ実施 外来2週間後`
    Generate. Confirm: output is Japanese, follows the 【患者】…【退院後の方針】
    structure, unknown items are marked 【要確認】, and no invented facts appear.
18. Repeat briefly for one more preset (e.g. 診療情報提供書 / Referral Letter).
    Confirm Japanese output. / 他のプリセットでも日本語出力を確認する。
19. Confirm generation speed is usable on this PC (rough guide: first tokens
    within ~30 s, then continuous streaming). Record subjective speed.

## F. Audit log & shutdown / 監査ログと終了

20. In Explorer, confirm a file like `audit\audit-YYYYMM.jsonl` exists on the
    stick and its modified time is "just now". / 監査ログファイルの更新を確認。
21. In Command Prompt, from the stick root, run:
    `bin\win-x64\auditgw.exe verify audit\audit-YYYYMM.jsonl`
    (use the real filename). Confirm it reports the chain as valid (exit
    without error). / ハッシュチェーン検証が成功することを確認する。
22. Run `STOP_WINDOWS.bat`. Confirm the console window closes and Task Manager
    shows **no** `auditgw.exe` or `llama-server.exe` remaining.
    終了後、タスクマネージャーに両プロセスが残っていないことを確認する。
23. Start it once more (`START_WINDOWS.bat`), confirm it comes up again cleanly,
    then stop it again. / 再起動→再停止が正常なことを確認する。
24. Eject the stick with "Safely Remove Hardware", reconnect the PC network if
    you disconnected it, and sign the stick back in on the custody register.
    安全な取り外し→ネットワーク復旧→台帳へ返却記録。

## G. Result / 判定

| # | Area / 項目 | Pass/Fail | Notes / 備考 |
|---|---|---|---|
| B | Launch & SmartScreen / 起動 | | |
| C | Startup / 起動動作 | | |
| D | Offline & loopback / オフライン | | |
| E | Functional (JA output) / 機能 | | |
| F | Audit log & shutdown / 監査ログ・終了 | | |

Overall / 総合判定:  PASS ・ FAIL
Signature / 署名: ______________
