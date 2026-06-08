# Phase 1 成功ロジックの整理

**最終達成**: 2025-12-03（251203 v3: 10回連続成功、定常偏差 std < 0.4 ns）
**成功コード**: `worklog/2025_semester_A/251203/frfr_package_1203_v3/`

## 1. Phase 1 の目標（何を成功と定義したか）

> 「FRFR（2台のOCXOの位相差）を**任意の一定値**で停止させる」

- 制御できるのは「止めること」のみ。**止まる値そのものは制御できない**（後で Phase 2 に持ち越し）
- オシロ上で FRFR の数字が動かなくなれば成功（= 2つの発振器が同じ周波数で回っている）
- 数値的には `std(FRFR) < 0.4 ns` を定常状態の成功基準とした

## 2. なぜこれで止まるのか（制御理論の観点）

### 2.1 プラントモデル

ao1 電圧 u [V] を入力、FRFR [ns] を出力とすると:

```
G(s) = K / s,   K ≈ +80.9 ± 1.7 [ns/(V·s)]
```

- **積分器プラント**（1/s）: 電圧は周波数オフセットを与え、位相差はその時間積分で溜まる
- 符号 `K > 0`: ao1 を上げると FRFR が増える方向に流れる
- この K は 251205/251208 のパルス応答実験と 260127-260129 の ao1 スイープで同定済み

### 2.2 Phase 1 の制御則

`run_frfr_fb_single.m` の核は以下:

```matlab
drift_ns  = frfr_corrected - prev_frfr_corrected;   % ΔFRFR [ns]
freq_err  = drift_ns / Ts;                          % ΔFRFR/Δt [ns/s]
dv        = -Kp * freq_err;                         % 傾きに比例して電圧を変える
v_ao1     = clamp(v_ao1 + dv, v_min, v_max);        % ★積分型更新★
outputSingleScan(s, [ao0_const, v_ao1]);
```

**パラメータ**（1203 v3）:
- `Ts = 0.3 s` （サンプリング周期）
- `Kp = 0.0001 V/(ns/s)`
- `freq_err_threshold = 0.3 ns/s` （このしきい値以下なら制御しない＝ハンチング防止）
- `min_step = 0.001 V` （離散 DAC 分解能）
- `ao0_const = 1.54 V`（基準側は固定）、`ao1_init = 1.54 V`

### 2.3 なぜ止まるかの数式的説明

離散プラント: `FRFR[k+1] = FRFR[k] + K·Ts·u[k]`
制御則: `u[k] = u[k-1] - Kp · (FRFR[k] - FRFR[k-1])/Ts`

これを展開して `u[0] = u_init` を初期条件とすると:

```
u[k] = u_init - (Kp/Ts) · (FRFR[k] - FRFR[0])
```

つまりこの制御則は、**「積分型更新」という書き方になっていても、実質は FRFR 値に対する比例制御**。閉ループ方程式は:

```
FRFR[k+1] = (1 - K·Kp) · FRFR[k] + K·Kp · FRFR[0]
```

閉ループ極: `z = 1 - K·Kp ≈ 1 - 80.9·0.0001 = 0.9919`（0 < |z| < 1 → 安定）

### 2.4 「任意の値で止まる」のはなぜか

閉ループは `FRFR[0]`（初期値）に収束する。
- 初期 FRFR は毎回ランダム（オシロ観測開始時点での位相差）
- よって「止まる位置」は run ごとに違うが、「止まる」ことそのものは保証される
- **これが Phase 1 の限界** → Phase 2 では `FRFR_ref` への収束を追加する

## 3. 再現性データ（10 Run 統計）

`frfr_steady_stats_20251203_142606.csv` より抜粋:

| Run | 定常 mean [ns] | 定常 std [ns] |
|-----|----------------|---------------|
| 1   | -8.80          | 0.198         |
| 2   | -71.84         | 0.352         |
| 3   | -40.88         | 0.399         |
| 4   | -33.21         | 0.197         |
| 5   | +63.53         | 0.284         |
| 6   | -7.04          | 0.360         |
| 7   | +7.29          | 0.165         |
| 8   | +30.60         | 0.263         |
| 9   | -42.58         | 0.390         |
| 10  | +71.61         | 0.226         |

- **10/10 すべてで停止に成功**（std < 0.4 ns）
- 定常平均値が run ごとにばらつく（-71.84 ～ +71.61 ns）＝まさに「任意の値で止まる」の証拠
- std の平均 ≈ 0.28 ns（計測分解能 0.01 ns と比べ約 30 倍以内）

## 4. 成功を支えた周辺テクニック

### 4.1 位相アンラップ（FRFR補正）

FRFR は 0-100 ns で折り返す（10 MHz = 周期 100 ns）。折り返しを跨いだ瞬間だけ `Δ ≈ ±100 ns` のジャンプが現れるので、それを検出してオフセットを加算:

```matlab
JUMP_DETECT_NS = 50;   % |Δ| > 50 ns なら折り返しとみなす
OFFSET_STEP_NS = 100;  % オフセット補正量
if delta_raw <= -JUMP_DETECT_NS
    frfr_offset = frfr_offset + OFFSET_STEP_NS;
elseif delta_raw >= +JUMP_DETECT_NS
    frfr_offset = frfr_offset - OFFSET_STEP_NS;
end
frfr_corrected = raw_frfr + frfr_offset;
```

これをしないと、折り返し瞬間に巨大な `freq_err` が算出されて電圧がキック → 発散する。

### 4.2 デッドバンド（freq_err_threshold）

`|freq_err| < 0.3 ns/s` なら電圧を変えない。
- 計測ノイズ由来の微小な drift でハンチングするのを防ぐ
- 定常状態を安定に維持する役割

### 4.3 複数 Run を自動実行するパッケージ化

`frfr_fb_experiment.m` で 10 Run を `pause(120)` 挟んで連続実行:
- 各 Run 間は `outputSingleScan(s, [0, 0])` で 0V に戻し、系を初期状態近くにリセット
- 統計的再現性を担保する仕掛け

### 4.4 安全装置

- `onCleanup` + `cleanupDAQ` で例外時も DAQ を 0V で解放
- `clamp(u, 0, 5)` で電圧飽和を明示的に実装
- `min_step = 0.001 V`（1 mV）で DAC 分解能に揃える

## 5. Phase 1 から Phase 2 への橋渡し

| 観点 | Phase 1 | Phase 2 |
|------|---------|---------|
| 目標 | 任意値で止める | 指定値 `FRFR_ref` に収束 |
| 制御則 | `dv = -Kp·freq_err` | `dv = Ki·e_phase - Kd·freq_err` |
| 誤差信号 | `freq_err` のみ | `e_phase` と `freq_err` の2項 |
| 更新形式 | 積分型 `u[k]=u[k-1]+dv` | 積分型（同じ） |
| 未知平衡電圧 `u_eq` | 自動追従 | 自動追従 |
| 閉ループ極 | `z ≈ 0.992`（1次） | `z ≈ 0.924±0.039j`（2次系、整定 15s） |

**重要**: 積分型更新の形は両 Phase で共通。Phase 1 の成功要因（積分器プラントに対する積分型制御則で平衡電圧を学習する）を Phase 2 でも継承している。

## 6. 発表用の要点（1スライド想定）

- **課題**: 2台の OCXO の周波数を同期（= 位相差を一定に保つ）
- **制御対象**: ao1 電圧 → OCXO-B 周波数 → FRFR は積分器プラント `G(s)=K/s`
- **Phase 1 制御則**: FRFR の傾き（周波数誤差）を 0 に戻すよう ao1 を積分的に更新
- **成果**: 10/10 成功、定常 std ≈ 0.28 ns（計測分解能の 30 倍以内）
- **残課題**: 「任意の値」→「指定の値」に拡張（Phase 2）

## 7. 参照ファイル一覧

- `worklog/2025_semester_A/251203/frfr_package_1203_v3/frfr_fb_experiment.m` - 10 Run ドライバ
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/run_frfr_fb_single.m` - 1 Run 制御ループ本体
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/analyze_frfr_all_runs.m` - 解析スクリプト
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/frfr_steady_stats_20251203_142606.csv` - 定常統計
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/frfr_overlay.pdf` - 10 Run 重ね書き図
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/steady_frfr_mean.pdf` - 定常平均の分布
- `worklog/2025_semester_A/251203/frfr_package_1203_v3/steady_frfr_std.pdf` - 定常 std の分布
