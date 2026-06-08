# 2026-05-18 やることリスト

## 測定タスク

- [ ] `frfr_phase2_fb_hold_off_260515_v1.m` を用いて **10分間の測定** を実施
  - デフォルト引数だと t_total = 900s (15分: FB 5分 + HOLD 5分 + OFF 5分)
  - **10分測定にする場合** は引数で短縮:
    ```matlab
    % 例1: そのまま 15 分（OFF 5 分込みでフル観察）
    result = frfr_phase2_fb_hold_off_260515_v1();

    % 例2: 10 分で終了させたい場合（OFF 区間なし、FB 5分 + HOLD 5分）
    result = frfr_phase2_fb_hold_off_260515_v1(600);

    % 例3: FB 5分 + HOLD 2.5分 + OFF 2.5分 を 10 分内に収める
    result = frfr_phase2_fb_hold_off_260515_v1(600, 25, 300, 450);
    ```
  - → 当日にどのパターンで回すか決める

## メモ

- 元コードは `260515/frfr_phase2_fb_hold_off_260515_v1.m`（ファイル名はそのままコピー）
- 動作: 0–5分 FB制御 / 5–10分 HOLD（FB終端電圧固定） / 10分以降 OFF（0V）
- ao0 単独構成 (ao1 未使用)、初期電圧 1.54 V、目標 FRFR デフォルト 25 ns
