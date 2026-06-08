# `frfr_phase2_fb_260512_v1.m` コード解説

Phase 2 FB スクリプト（ao0 単独構成版）の実装ロジックを上から順に説明する。
行番号は実ファイル基準。

---

## ① 関数シグネチャと引数（L1, L27-28）

```matlab
function result = frfr_phase2_fb_260512_v1(t_total, FRFR_ref)
if nargin < 1 || isempty(t_total),  t_total  = 300; end
if nargin < 2 || isempty(FRFR_ref), FRFR_ref = 25;  end
```
- `function` にしてワークスペース汚染を防ぐ（CLAUDE.md のコーディング規約）
- 引数省略時のデフォルト: 300秒, 目標 25 ns
- `result` 構造体で実行結果を返す

---

## ② ハードウェア初期化（L30-41）

```matlab
s = daq.createSession('ni');
addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % ao0 のみ

ip  = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 5;

SAFE_AO0 = 0.0;
c = onCleanup(@() cleanupDAQ(s, dev, SAFE_AO0));
```
- **NI DAQ セッション**: ao0 だけを追加（260421 版は ao0+ao1、今回は ao0 単独構成）
- **VISA**: オシロ (192.168.1.61) を TCPIP で開く。Timeout 5秒
- **`onCleanup`** が肝: 関数が**正常終了でも例外でも Ctrl+C でも**必ず `cleanupDAQ` を呼ぶ → 0V に戻して release。OCXO が変な電圧で取り残されない保険

---

## ③ 制御パラメータ（L43-66）

```matlab
Ts = 0.3;               % サンプリング周期
u_init = 1.54;          % ao0 初期値
v_min = 0.0; v_max = 5.0;

Ki = 0.0003;            % 位相誤差ゲイン
Kd = 0.0018;            % 周波数誤差ゲイン
du_max = 0.05;          % レートリミット

T_period     = 100;     % FRFR の周期 [ns]
JUMP_DETECT  = 50;      % ジャンプ閾値
OFFSET_STEP  = 100;     % アンラップ補正量
```
すべて変数で持っているのは、ループ中に値が変わらないものを **「明示的に1箇所で定義」** するため。後でゲイン調整するとき探しやすい。

---

## ④ 状態変数（L68-72）

```matlab
prev_raw_frfr       = NaN;    % 前回の生 FRFR（アンラップ用）
frfr_offset         = 0;      % アンラップで足し算するオフセット
prev_frfr_unwrapped = NaN;    % 前回のアンラップ後 FRFR（freq_err 用）
target_adjusted     = NaN;    % 起動時に決定される実目標
```
- `NaN` 初期化: 「まだ値が無い」ことの目印。最初のイテレーションだけ特殊処理するために使う
- これらは**ループ間で値を受け渡す状態**

---

## ⑤ ログ配列（L74-81）

```matlab
time_log = []; frfr_raw_log = []; frfr_unwrap_log = [];
e_phase_log = []; freq_err_log = []; delta_u_log = []; ao0_log = [];
```
ループ中に `end+1` で末尾追加（`%#ok<AGROW>` で警告抑制）。MATLAB 的には事前確保した方が速いが、Ts=0.3 のループでは無視できる程度。

---

## ⑥ 初期出力（L83-89）

```matlab
u_applied = clamp(u_init, v_min, v_max);
outputSingleScan(s, u_applied);
```
ループに入る前に **1.54V を ao0 に印加**。これで OCXO はおよそ平衡点へ。

---

## ⑦ メインループ（L91-174）— ここが本体

### 7-1. 時刻管理（L94-96）
```matlab
t = seconds(datetime('now') - t_start);
if t > t_total, break; end
```
`pause(Ts)` だけだと累積誤差が出るので、**経過時刻の絶対時刻ベース計算** で打ち切り判定。

### 7-2. FRFR 読み取り（L99-106）
```matlab
writeline(dev, "MEAS:ADV:P3:VAL?");
frfr_sec = str2double(readline(dev));
raw_frfr = frfr_sec * 1e9;     % 秒 → ナノ秒
```
オシロは秒単位で返すので 1e9 倍。`try/catch` で通信エラーで止まらないようにし、エラー時はループ脱出。

### 7-3. アンラップ（L109-118）— トリッキー
```matlab
if ~isnan(prev_raw_frfr)
    delta_raw = raw_frfr - prev_raw_frfr;
    if delta_raw <= -JUMP_DETECT      % +50 → -50 に飛んだ
        frfr_offset = frfr_offset + OFFSET_STEP;
    elseif delta_raw >= +JUMP_DETECT  % -50 → +50 に飛んだ
        frfr_offset = frfr_offset - OFFSET_STEP;
    end
end
frfr_unwrapped = raw_frfr + frfr_offset;
prev_raw_frfr = raw_frfr;
```
- 生 FRFR は [-50, +50] でラップする
- ラップ瞬間は `delta_raw` が ±100 近くになる → 50 を閾値にラップ検出
- 検出時に `frfr_offset` を ±100 ずらして、見かけ上の連続位相 `frfr_unwrapped` を維持
- **初回は `prev_raw_frfr=NaN` なので何もしない**（NaN ガード）

例: raw が `+48 → -49`（ラップ）なら `delta=-97 < -50` → offset+=100 → unwrap=-49+100=+51 ✓

### 7-4. 目標値の自動調整（L121-130, 初回のみ）
```matlab
if isnan(target_adjusted)
    remainder = mod(frfr_unwrapped - FRFR_ref, T_period);
    if remainder > T_period / 2
        remainder = remainder - T_period;
    end
    target_adjusted = frfr_unwrapped - remainder;
end
```
- `FRFR_ref = 25` を指定しても、初期 FRFR が例えば 72 ns だったら、**最短経路の目標は 125 ns**（位相は周期等価）
- `mod` と「半周期超なら 100 引く」で **初期 FRFR から最短距離の `FRFR_ref + N*100`** を計算
- これを以降固定で使う

### 7-5. 誤差計算（L133-141）
```matlab
e_phase = target_adjusted - frfr_unwrapped;

if isnan(prev_frfr_unwrapped)
    freq_err = 0;                              % 初回は 0 で初期化
else
    freq_err = (frfr_unwrapped - prev_frfr_unwrapped) / Ts;
end
prev_frfr_unwrapped = frfr_unwrapped;
```
- `e_phase`: 位置誤差 [ns]
- `freq_err`: 速度 [ns/s]、差分近似
- 初回は前の値がないので `freq_err=0`

### 7-6. 制御則（L144-150）
```matlab
delta_u = Ki * e_phase - Kd * freq_err;
delta_u = clamp(delta_u, -du_max, du_max);
u_next  = clamp(u_applied + delta_u, v_min, v_max);
```
- **本体は 1 行**: `Ki·e − Kd·df`
- レートリミット (du_max): 1 ステップ 0.05V を超える変化を禁止 → 急なアクセル防止
- 電圧クランプ (0-5V): DAQ 物理範囲

### 7-7. 出力 & ログ（L153-168）
```matlab
outputSingleScan(s, u_next);
u_applied = u_next;
% ... 各ログ配列に append ...
```
- 計算した電圧を即時出力
- `u_applied` を次ループの起点として保存

### 7-8. ループ末尾（L170-173）
```matlab
fprintf("t=%6.1f | FRFR=%.2f ns | e=%.2f ns | df=%.3f ns/s | du=%.5f | ao0=%.4f V\n", ...);
pause(Ts);
```
コンソール出力 + Ts 秒待ち。`pause` は粗いタイマーだが Ts=0.3 程度なら十分。

---

## ⑧ ループ後処理（L178-211）

### CSV 保存
```matlab
log_tbl = table( time_log(:), ..., 'VariableNames', {'time_s', ...});
writetable(log_tbl, log_name);
```
**1 ループ 1 行のテーブル化**（後で他の解析スクリプトから読みやすい形式、CLAUDE.md 規約）。

### プロット 3 枚（L193-211）
1. FRFR vs Time + 目標値の水平線
2. Phase Error vs Time
3. Control Voltage (ao0) vs Time

それぞれ `exportgraphics` で PDF 化（規約: `saveas` 不可）。

---

## ⑨ 定常状態統計（L226-239）

```matlab
idx_ss = time_log > (max(time_log) - 60);    % 最後の60秒
ss_mean = mean(frfr_unwrap_log(idx_ss));
ss_std  = std(frfr_unwrap_log(idx_ss));
ss_err  = mean(e_phase_log(idx_ss));
```
- **最後の 60 秒** を「定常」と見なして mean/std/平均誤差を算出
- これが「目標 25ns に対して 25.0 ± 0.3 ns で収束」のような中間発表の主要指標になる

---

## ⑩ ヘルパー関数（L242-251）

```matlab
function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
```
- `clamp`: 値域制限の小道具
- `cleanupDAQ`: 各 `try`/`catch` で囲んでいるのは「途中で失敗しても残りの後始末は続行する」ため。安全装置の最終砦

---

## 直感（車のアナロジー）

| 制御の言葉 | 車の言葉 |
|---|---|
| FRFR（位相差 [ns]） | 車の **位置** [m] |
| dFRFR/dt（位相速度） | 車の **速度** [m/s] |
| ao0 電圧 [V] | アクセル **踏み量** [%] |
| K（プラントゲイン） | アクセル → 加速度の変換係数 |
| FRFR_ref（目標位相差） | **停めたい場所** [m] |

> 「アクセル踏み量を変えて、ある地点で速度ゼロにする」問題そのもの。

- ① **遠ければアクセル足す** → `Ki * e_phase`（距離に比例した踏み増し）
- ② **速く動いてたらアクセル戻す** → `-Kd * freq_err`（ブレーキ的効果）
- ③ この 2 つを合わせた「今このループでのアクセル変化」 = `delta_u`
- ④ 前のアクセル量に足す。**「絶対的なアクセル量を指示する」のではなく「微調整を積み重ねる」のがミソ**

### なぜ「積分型更新」 (`u[k+1] = u[k] + …`) が肝か

普通の比例制御だと「u = u0 − k·e」と**絶対値で指令**する。これは:

> 「目標との距離 e が 0 になったら、アクセルは u0 という決め打ち値になる」

を意味する。でもこの研究の問題は **「2つの OCXO が完全に同周波数になるアクセル踏み量 u_eq は事前に分からない」** こと（OCXO 個体差、温度ドリフトなどで毎回違う）。

→ u0 を勘で決めると、ずっとズレた値で停まり続ける（定常偏差が残る）

積分型更新 `u[k+1] = u[k] + …` なら:
- e_phase が残っている限り u が動き続ける
- e_phase = 0 になった時点で u は自動的に「いま必要な値」に落ち着く
- u_eq を知る必要がない

これが **「Phase 1 でうまく行った積分型更新を、目標値追従に拡張した」** という Phase 2 の本質（4/21 ノートの設計議論）。

---

## ロジックの要約図

```
[入力] FRFR_ref, t_total
   ↓
[初期化] DAQ + scope + onCleanup + 1.54V 出力
   ↓
[ループ @ Ts=0.3s] ────────────────────┐
   FRFR読む → アンラップ → 誤差計算    │
   delta_u = Ki·e - Kd·df              │
   clamp(rate) → clamp(0-5V) → 出力    │
   ログ append                          │
   pause(0.3s) ─────────────────────────┘
   ↓
[終了] CSV保存 + プロット3枚 + 定常状態統計
   ↓
[cleanup] 0V出力 → release (onCleanup経由)
```

---

## 安全装置（コードに散らばっている小ネタ）

| 何 | 目的 |
|---|---|
| `clamp(u, 0, 5)` | NI DAQ の物理出力範囲を超えない |
| `clamp(delta_u, -du_max, du_max)` | 1ステップで急にアクセル踏み込まない（レートリミット） |
| `onCleanup` | 異常終了でも 0V に戻す（OCXO 暴走防止） |
| アンラップ処理 | FRFR が [-50, +50] ns でラップするのを内部で連続軸に展開 → 制御則が「不連続なジャンプ」に騙されない |
| `try/catch` (VISA, DAQ output) | 通信エラーでループ脱出するが、cleanupは確実に走る |

---

## なぜ Ki, Kd を「設計」するのか

`Ki` と `Kd` は感度ノブで、大きすぎると **発振**、小さすぎると **遅い**:
- 大きい → 「急ブレーキ・急アクセルを繰り返す」 → オーバーシュート/振動
- 小さい → 「ゆっくり寄っていく」 → 整定時間が伸びる

設計ノート（260421）では「ω_n=0.3 rad/s（応答の速さ）、ζ=0.8（減衰の度合い）」を狙って Ki=0.0003, Kd=0.0018 を決めている。

---

## 関連ファイル

- 本体スクリプト: `frfr_phase2_fb_260512_v1.m`
- 設計ノート: `worklog/2025_semester_A/260421/analysis_notes_260421.md`
- 旧版（ao0+ao1 構成）: `worklog/2025_semester_A/260421/frfr_phase2_fb_260421_v1.m`
- 符号確認: `frfr_sign_test_260512.m`
