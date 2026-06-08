# 先行研究調査 — 複数OCXO位相同期・関連領域

**調査日**: 2026-04-21
**目的**: 2台OCXOの位相同期 → 複数発振器への拡張について、既存研究・既存技術の位置づけを把握する。

## 0. エグゼクティブサマリ

- **2台OCXOのデジタル位相同期制御**そのものは、GPSDO（GPS Disciplined Oscillator）という成熟技術として広く存在する。GPS由来の1PPS信号を基準にOCXOを電圧制御でPLLする仕組み。
- **アナロジー構造は同じ**（位相比較 → ループフィルタ → 電圧制御）だが、本研究は"基準側もOCXO"という点、"VISA経由でオシロから位相差を読む"という点、"MATLAB上でFBロジックを書く教育的構成"という点で独自。
- **複数OCXO化**は時刻保持・通信ネットワーク分野で"クロック アンサンブル"として研究されており、カルマンフィルタ時刻スケール・White Rabbit（サブナノ秒PTP）などの成熟分野がある。Kuramoto モデル（結合発振器）は理論的バックグラウンド。
- **本研究のスタンス**: 産業界の成熟技術を参考にしつつ、「シンプルな教育的プラットフォームで、状態空間制御の枠組みで位相同期を定式化する」ことが独自性の核。

## 1. 2台OCXO位相同期の関連研究

### 1.1 GPSDO (GPS Disciplined Oscillator)

2台目の OCXO の代わりに GPS 受信機の 1PPS を基準とする構成。本研究の "OCXO-A を基準" の部分を "GPS 1PPS" に置き換えたもの。

**構成要素**（本研究との対応）:

| GPSDO | 本研究 |
|-------|--------|
| GPS 1PPS（基準） | OCXO-A（基準） |
| 1PPS 位相比較器 | オシロ MEAS:ADV:P3（CH1→CH2 時間差） |
| マイコン内のPID/PLLソフトウェア | MATLAB のFBロジック |
| DAC → VCXO/OCXO EFC 電圧 | NI DAQ ao1 → OCXO-B EFC |

**ポイント**:
- 制御アルゴリズムはほぼ必ず "PID を PLL 内に組み込む" 形（PID controller as loop filter of PLL）
- ハードウェア（MAX1932 などの高分解能 DAC、低ノイズ電源）も実用では重要
- 学習効果（エージング・温度補償）まで入った実装もあり

**本研究との違い**:
- 本研究は基準側も OCXO（GPS 非依存）。これは"基準がない分散環境"で同期を作る研究に対応
- FBロジックを MATLAB で書く → 制御理論の試行錯誤が容易（教育的）
- サンプリング周期 0.3 s と相対的にゆっくり（GPSDO は通常 1 Hz）

**参照**:
- Wikipedia: GPS disciplined oscillator
- Methodological approach to GPS disciplined OCXO based on PID PLL (ResearchGate)
- Analog Devices: Phase-Locked Loop (PLL) Fundamentals

### 1.2 電子周波数制御 (EFC) 技術

OCXO 内部のバラクタを制御電圧で引っ張り、水晶の負荷容量を変えて共振周波数を数 ppb 単位で調整する手法。本研究の ao1 → OCXO-B の部分。

- OCXO の EFC 感度は 5-10 ppb/V 程度（TCXO の 50-100 ppb/V より鋭敏＝安定）
- 本研究で同定した K ≈ 80.9 ns/(V·s) は、周期換算すると約 0.81 ppb/V の感度（微弱だが十分同期可能）
- 電圧出力のノイズが直接位相ノイズになるので、DAC 分解能（本研究は 1 mV ステップ）が精度を決める

**参照**: Bliley blog, Mouser TCXO vs OCXO 比較資料

### 1.3 古典 PLL とデジタル PLL

Phase-Locked Loop の基礎。以下3要素から成る:
1. 位相比較器（PFD / digital phase detector）
2. ループフィルタ（実装上は PID コントローラで代替できる）
3. VCO / VCXO / OCXO

本研究の構造はまさに digital PLL の教科書的な構成:
- 位相比較器 = オシロの MEAS:ADV:P3（時間領域の時間差計測）
- ループフィルタ = MATLAB の FBロジック（現行は PI-D）
- VCO = OCXO-B

**参照**: Zurich Instruments White Paper on PLL, Wikipedia PLL

## 2. 複数OCXOへの拡張関連

### 2.1 クロックアンサンブル（時刻スケール生成）

N 台の時計（原子時計・OCXOなど）から合成時刻を作る分野。本研究の Phase 3 以降（N台に拡張）と直結する。

**主要手法**:

| アルゴリズム | 特徴 |
|-------------|------|
| AT1 / AT2 (NIST) | 重み付け平均。重みは Allan 分散で決定 |
| Natural Kalman (NKT) | 時計状態を2状態（位相・周波数）で Kalman 推定 |
| Reduced Kalman (RKT) | 次元削減で実装負荷軽減 |
| Two-stage Kalman (TKT) | 観測と推定を二段階に分離 |

**ポイント**:
- 各時計の状態は `[phase; frequency offset; frequency drift]` の 2-3 次元
- 本研究の 2状態 FB（FRFR + dFRFR/dt）はこれの最小版に相当
- N 台に拡張するときは、時刻スケール側で Kalman フィルタによる状態推定 → 各時計にフィードバックが標準構造

**参照**:
- arxiv 2305.05894: "Structured Kalman Filter for Time Scale Generation in Atomic Clock Ensembles"
- arxiv 2504.15540: "Explicit Ensemble Mean Clock Synchronization for Optimal Atomic Time Scale Generation"
- MDPI 2023: "Clock Ensemble Algorithm Test in the Establishment of Space-Based Time Reference"

### 2.2 White Rabbit（サブナノ秒 PTP）

CERN + GSI 発の Ethernet ベース時刻/周波数分配プロトコル。本研究の「複数OCXOを同期」の、産業界での到達点の一つ。

**特徴**:
- IEEE 1588 (PTP) + SyncE + 位相計測
- 5 km 光ファイバで < 1 ns (precision 10 ps) 達成
- 金融、加速器、ラジオ天文などで運用
- 各ノードが OCXO / TCXO / Rb 発振器を持ち、PTP メッセージと位相測定で全体同期

**本研究との関係**:
- 本研究は「2台→多数」の最小単位を扱うので、White Rabbit の "各ノード内の規律ループ" に相当する部分を深掘りする位置付け
- 実装レベルでは、本研究の FB ロジックが White Rabbit ノードの"心臓部"と同じ問題を解いている

**参照**:
- white-rabbit.web.cern.ch
- Oscilloquartz "What are White Rabbit timing systems?"
- Safran Navigation & Timing: White Rabbit Solutions

### 2.3 IEEE 1588 PTP / Holdover

通信ネットワークで採用されているクロック同期規格。Holdover（上流参照喪失時の自走維持）の観点で OCXO の選定が議論される。

- OCXO による holdover: 8 μs over 8-24 h
- システムレベルで温度補正・経年補正を外付けするアプローチも一般化
- 本研究の PI-D 制御は、ある意味「holdover ではない通常運用」に相当

**参照**:
- Wikipedia: Holdover in synchronization applications
- Skyworks AN1208 / AN1307
- EE Times: "Understanding the concepts of synchronization and holdover"

### 2.4 Kuramoto モデル（結合発振器の理論）

N 個の発振器がある結合強度で結ばれたとき、臨界結合 K_c を超えると位相同期が出現するという理論モデル。

```
dθ_i/dt = ω_i + (K/N) Σ_j sin(θ_j - θ_i)
```

**本研究との関係**:
- 本研究は「全結合ではなく、中央コントローラ経由の同期」という形態（Kuramoto はピアツーピア）
- ただし Phase 4 の「ミキサーを使った同期」はアナログ結合そのもので、Kuramoto に近い
- N 台拡張時に「スター型 vs 全結合」の設計トレードオフを議論する材料

**参照**:
- Wikipedia: Kuramoto model
- "The Kuramoto model: a simple paradigm for synchronization phenomena" (scala.uc3m.es)

## 3. 本研究のポジショニング

```
                          [個別技術]
                               ↑
                               │
 [教育的実装] ────────── 本研究 ────────── [産業実装]
                               │
                               ↓
                       [理論的枠組み]
```

| 軸 | 位置 |
|----|------|
| 教育的実装 | MATLAB + NI DAQ + 市販オシロで「中身が見える」制御を作る。学生が制御理論の試行錯誤を体験できる。 |
| 産業実装 | GPSDO / White Rabbit 等の商用技術。完成度は高いが中身はブラックボックス。 |
| 個別技術 | EFC 電圧感度、DAC 分解能、位相比較器精度などの要素技術。 |
| 理論的枠組み | 状態空間制御、LQR/Kalman、Kuramoto モデル。 |

**独自性の核**:
1. **状態空間制御の定式化**を実物のOCXO系で実証する（多くの GPSDO は PI で済ませている）
2. **中央コントローラ型の多発振器同期**をスケーラブルに構築する最小単位の研究
3. **MATLAB 上での試行錯誤ループ**によって制御理論の実地検証になっている

## 4. 発表で引用しそうな文献（中間時点の候補）

| 分類 | 文献 | 使いどころ |
|------|------|-----------|
| GPSDO 基礎 | Methodological approach to GPS disciplined OCXO based on PID PLL (ResearchGate) | 2台同期の先行技術として言及 |
| PLL 理論 | Analog Devices "PLL Fundamentals" | 位相比較 + ループフィルタの構造 |
| 時刻スケール | arxiv 2305.05894 (Structured Kalman Filter) | N 台拡張時の状態推定 |
| 精密分配 | CERN White Rabbit 論文 (IEEE 2011) | サブナノ秒級同期の到達点 |
| 結合発振器 | Kuramoto (1984) | ミキサー同期 (Phase 4) の理論背景 |

## 5. 追加調査が必要な項目

中間発表後に深掘りする候補:
- [ ] OCXO の Allan 分散特性と、本研究で FB 制御によって改善できる時間スケールの定量評価
- [ ] ループ帯域設計（Phase 2 の整定 15 s は OCXO の holdover 要件と整合するか）
- [ ] 多発振器を扱う時の観測ハードウェア（N 台の位相差をどう同時測定するか）
- [ ] Kuramoto 的な peer-to-peer 結合 vs 中央コントローラ型のメリデメ
- [ ] ミキサー結合（Phase 4）を state-space 制御で扱う際の非線形性の影響

## 6. 参照 URL 一覧

### 2台OCXO同期 / GPSDO / PLL
- https://en.wikipedia.org/wiki/GPS_disciplined_oscillator
- https://www.researchgate.net/publication/251900137_Methodological_approach_to_GPS_disciplined_OCXO_based_on_PID_PLL
- https://www.analog.com/en/resources/analog-dialogue/articles/phase-locked-loop-pll-fundamentals.html
- https://www.zhinst.com/sites/default/files/documents/2022-09/zi_whitepaper_phase_locked_loop.pdf
- https://blog.bliley.com/electronic-frequency-control-methods
- https://blog.bliley.com/what-are-gps-disciplined-oscillators-gpsdo-applications

### クロックアンサンブル / 時刻スケール
- https://arxiv.org/abs/2305.05894 (Structured Kalman Filter)
- https://arxiv.org/html/2504.15540v2 (Ensemble Mean Clock Synchronization)
- https://www.mdpi.com/2072-4292/15/5/1227 (Clock Ensemble Algorithm Test)

### White Rabbit / PTP
- https://white-rabbit.web.cern.ch/documents/White_Rabbit-a_PTP_application_for_robust_sub-nanosecond_synchronization.pdf
- https://www.oscilloquartz.com/en/products-and-services/technology/what-are-white-rabbit-timing-systems
- https://en.wikipedia.org/wiki/White_Rabbit_Project

### Holdover / 通信同期
- https://en.wikipedia.org/wiki/Holdover_in_synchronization_applications
- https://www.skyworksinc.com/-/media/Skyworks/SL/documents/public/application-notes/an1208-osc-ieee-1588v2-requirements.pdf
- https://www.eetimes.com/understanding-the-concepts-of-synchronization-and-holdover/

### Kuramoto / 結合発振器
- https://en.wikipedia.org/wiki/Kuramoto_model
- https://scala.uc3m.es/publications_MANS/PDF/finalKura.pdf
- https://www.nature.com/articles/srep21926
