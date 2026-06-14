function result = frfr_phase2_model_260608_v1(opts)
%====================================================================
% Phase 2 モデルベースFB (260608 v1)  ── 方向2：ω=ω0(1+N/400) を使った制御則
%
% 着想:
%   実測で「1 LSB(305µV) → FRFR が 0.26 ns/s ドリフト」(260605)。
%   FRFR周期は100ns なので 100/0.26≈385≈400 s → 1 LSB あたり FRFR が
%   1周(100ns)するのに約400秒 = 周回率 N/400 [周/s]（N=動作点からのLSB段数）。
%   これが ω = ω0(1 + N/400) の意味。
%
%   そこでプラントを陽にモデル化:   df = g_LSB * N     [ns/s]
%     df    : FRFR ドリフト速度(=周波数誤差) [ns/s]
%     N     : 周波数一致点からの制御電圧の LSB 段数（整数）
%     g_LSB : 1 LSB あたりの df 変化 ≈ 0.26 ns/s  (260605 実測)
%
%   逆モデルで「欲しい df を出すのに必要な LSB 数」を直接指令する:
%     1) 位相誤差 e から望ましいドリフト   df_des = clamp(Kp_e*e, ±df_max)
%     2) 必要な LSB 増分                   dN = (df_des - df) / g_LSB
%     3) 整数LSBへ丸め＋レート制限         dN = round(clamp(dN, ±dN_max))
%     4) 出力                              u  = clamp(u + dN*lsb_V, 0..5)
%
%   ★ round() が肝: 必要補正が 1LSB 未満なら dN=0 → 電圧据え置き。
%     誤差が 1LSB 分たまるまで動かさない＝量子化由来の自然なデッドバンド。
%     260604「電圧を動かさないほど静か」を制御則に内包し、ハンチング注入を抑える。
%
%   ★ df ノイズ対策: FRFR は ~ns 分解能 → df=ΔFRFR/Ts はノイズが乗る。
%     nOS平均 + EMA平滑(df_ema) + Ts長めで ±1LSB のバタつきを抑える。
%
% 区間（既定 各 slot_s 秒, 連続して状態を引き継ぐ）:
%   1. acq    MODEL : モデルFBで同期確立（ウォームアップ）
%   2. model  MODEL : モデルFB本番（評価対象）
%   3. HOLD   HOLD  : 電圧固定（無制御の基準, 260604で最良34ps）
%
% 評価: 各区間 終端60s std [ns]、FB区間は電圧移動量Σ|du| と LSB操作回数。
% WAV対応: 表示の「t=0 絶対時刻」をメモ → segmap.csv 窓に合わせて録音解析。
%
% 使い方（Current Folder を 260608 に）:
%   frfr_phase2_model_260608_v1();                 % 既定（各 slot_s）
%   o.slot_s = 60; frfr_phase2_model_260608_v1(o); % 動作確認（各1分）
%
% opts（既定）: slot_s(180) FRFR_ref(25) u_init(1.54)
%              g_LSB(0.26) Kp_e(0.02) df_max(1.0) dN_max(3) df_ema(0.5)
%              Ts(1.0) nOS(3) dac_range_V(20) dac_bits(16) run_tag('')
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('slot_s',180, 'FRFR_ref',25, 'u_init',1.54, ...
                 'g_LSB',0.26, 'Kp_e',0.02, 'df_max',1.0, 'dN_max',3, ...
                 'df_ema',0.5, 'Ts',1.0, 'nOS',3, ...
                 'dac_range_V',20, 'dac_bits',16, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    Ts = opts.Ts;  nOS = opts.nOS;
    g_LSB = opts.g_LSB;  Kp_e = opts.Kp_e;  df_max = opts.df_max;
    dN_max = opts.dN_max;  ema = opts.df_ema;
    lsb_V = opts.dac_range_V / 2^opts.dac_bits;     % 1 LSB [V] ≈ 305 µV

    %% === 区間定義 ======================================================
    %            name     mode
    SEG = [ ...
        mkseg('acq',   'MODEL'); ...
        mkseg('model', 'MODEL'); ...
        mkseg('HOLD',  'HOLD')];

    %% === 共通定数 ======================================================
    v_min = 0.0;  v_max = 5.0;
    T_period = 100; JUMP_DETECT = 50; OFFSET_STEP = 100;

    %% === DAQ / Scope ===================================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;
    SAFE_AO0 = 0.0;
    c = onCleanup(@() cleanupDAQ(s, dev, SAFE_AO0)); %#ok<NASGU>

    %% === 状態（区間をまたいで連続）=====================================
    prev_raw_frfr = NaN;  frfr_offset = 0;  prev_frfr_unwrapped = NaN;
    target_adjusted = NaN;  t_prev = NaN;  df_s = 0;   % df の平滑値
    u_applied = clamp(opts.u_init, v_min, v_max);

    %% === ログ ==========================================================
    L = struct('t',[], 'seg',strings(0,1), 'mode',strings(0,1), 'dt',[], ...
               'raw',[], 'unw',[], 'e',[], 'df',[], 'df_s',[], 'df_des',[], ...
               'dN',[], 'du',[], 'ao0',[]);
    segmap = struct('name',{}, 'mode',{}, 't_start',{}, 't_end',{});

    %% === 開始（最初から u_init を出す = 0526/0604 と同じ起動）==========
    t_run_start = datetime('now');
    outputSingleScan(s, u_applied);
    fprintf("=== モデルベースFB v1 開始 ===\n");
    fprintf("スクリプト t=0 (絶対時刻): %s\n", datestr(t_run_start, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(">>> 録音併用なら開始時刻をメモ（WAV対応に使う）<<<\n");
    fprintf("各区間 %.0f s | 目標 FRFR=%.1f ns | u_init=%.3f V\n", opts.slot_s, opts.FRFR_ref, u_applied);
    fprintf("モデル: df=g_LSB*N, g_LSB=%.3f ns/s/LSB (1LSB=%.1f µV) | Kp_e=%.3f df_max=%.2f dN_max=%d ema=%.2f Ts=%.2f nOS=%d\n", ...
        g_LSB, lsb_V*1e6, Kp_e, df_max, dN_max, ema, Ts, nOS);

    %% === 区間ループ ====================================================
    for iseg = 1:numel(SEG)
        seg = SEG(iseg);
        seg_t0 = seconds(datetime('now') - t_run_start);
        fprintf("\n===== 区間 %d/%d: %-6s [%s] =====\n", iseg, numel(SEG), seg.name, seg.mode);

        seg_started = false;
        while true
            t = seconds(datetime('now') - t_run_start);
            if seg_started && (t - seg_t0 > opts.slot_s), break; end
            seg_started = true;

            % ---- FRFR 読み取り（nOS 回中央値）----
            raw_vals = nan(1, nOS);  read_ok = true;
            for k = 1:nOS
                try
                    writeline(dev, "MEAS:ADV:P3:VAL?");
                    raw_vals(k) = str2double(readline(dev)) * 1e9;
                catch ME
                    warning("FRFR read error: %s", ME.message); read_ok = false; break;
                end
            end
            if ~read_ok, break; end
            raw_frfr = median(raw_vals, 'omitnan');

            % ---- アンラップ ----
            if ~isnan(prev_raw_frfr)
                d = raw_frfr - prev_raw_frfr;
                if     d <= -JUMP_DETECT, frfr_offset = frfr_offset + OFFSET_STEP;
                elseif d >= +JUMP_DETECT, frfr_offset = frfr_offset - OFFSET_STEP; end
            end
            frfr_unw = raw_frfr + frfr_offset;
            prev_raw_frfr = raw_frfr;

            % ---- 周波数誤差 df = dFRFR/dt [ns/s]（公称Tsで割る）＋EMA平滑 ----
            dt = t - t_prev;   % 実周期（ログ用のみ）
            if isnan(prev_frfr_unwrapped)
                df = 0;  df_s = 0;
            else
                df = (frfr_unw - prev_frfr_unwrapped) / Ts;
                df_s = ema*df_s + (1-ema)*df;     % 平滑化
            end
            prev_frfr_unwrapped = frfr_unw;  t_prev = t;

            % ---- 目標（初回で確定）----
            if isnan(target_adjusted)
                rem = mod(frfr_unw - opts.FRFR_ref, T_period);
                if rem > T_period/2, rem = rem - T_period; end
                target_adjusted = frfr_unw - rem;
                fprintf("初期 FRFR=%.2f → 調整後目標=%.2f ns\n", frfr_unw, target_adjusted);
            end
            e = target_adjusted - frfr_unw;       % [ns]  (>0: frfrを増やしたい→df>0が欲しい)

            % ---- 制御則（逆モデル）----
            if strcmp(seg.mode, 'MODEL')
                % 1) 位相誤差 → 望ましいドリフト
                df_des = clamp(Kp_e * e, -df_max, df_max);          % [ns/s]
                % 2) 必要な LSB 増分（df_des を出すのに足りない分）
                dN_f = (df_des - df_s) / g_LSB;                     % [LSB]
                % 3) 整数LSBに丸め＋レート制限（小補正は 0 → 電圧据え置き）
                dN = round(clamp(dN_f, -dN_max, dN_max));
                % 4) 出力電圧
                du = dN * lsb_V;
                u_next = clamp(u_applied + du, v_min, v_max);
            else  % HOLD
                df_des = NaN;  dN = 0;  du = 0;  u_next = u_applied;
            end

            % ---- 出力 ----
            try
                outputSingleScan(s, u_next);
            catch ME
                warning("DAQ output error: %s", ME.message); break;
            end
            u_applied = u_next;

            % ---- ログ ----
            L.t(end+1)=t; L.seg(end+1,1)=seg.name; L.mode(end+1,1)=seg.mode; %#ok<AGROW>
            L.dt(end+1)=dt; L.raw(end+1)=raw_frfr; L.unw(end+1)=frfr_unw; %#ok<AGROW>
            L.e(end+1)=e; L.df(end+1)=df; L.df_s(end+1)=df_s; %#ok<AGROW>
            L.df_des(end+1)=df_des; L.dN(end+1)=dN; L.du(end+1)=du; L.ao0(end+1)=u_applied; %#ok<AGROW>

            fprintf("t=%6.1f [%-5s %s] FRFR=%.2f e=%.2f df=%.3f(s=%.3f) df*=%.3f dN=%+d ao0=%.4f\n", ...
                t, seg.name, seg.mode, frfr_unw, e, df, df_s, df_des, dN, u_applied);

            pause(Ts);
        end

        seg_t1 = seconds(datetime('now') - t_run_start);
        segmap(end+1) = struct('name',seg.name, 'mode',seg.mode, ...
            't_start',seg_t0, 't_end',seg_t1); %#ok<AGROW>
    end
    fprintf("\n=== モデルベースFB v1 終了 ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    log_name = sprintf('frfr_model_%s%s.csv', ts, tag);
    seg_name = sprintf('frfr_model_%s%s_segmap.csv', ts, tag);

    writetable(table(L.t(:), L.seg(:), L.mode(:), L.dt(:), L.raw(:), L.unw(:), ...
        L.e(:), L.df(:), L.df_s(:), L.df_des(:), L.dN(:), L.du(:), L.ao0(:), ...
        'VariableNames', {'time_s','segment','mode','dt_actual_s','frfr_raw_ns', ...
        'frfr_unwrapped_ns','e_phase_ns','freq_err_ns_per_s','freq_err_smooth_ns_per_s', ...
        'df_des_ns_per_s','dN_lsb','delta_u_V','ao0_V'}), log_name);
    fprintf("ログ保存: %s\n", log_name);

    smt = struct2table(segmap);
    smt.abs_start = string(datestr(t_run_start + seconds([segmap.t_start]'), 'HH:MM:SS'));
    writetable(smt, seg_name);
    fprintf("区間時刻表: %s\n", seg_name);

    %% === 区間サマリ（終端60s std と 電圧移動量・LSB操作回数）==========
    fprintf("\n--- 区間サマリ（終端60sのstd ↓ほどハンチング小）---\n");
    for k = 1:numel(segmap)
        sm = segmap(k);
        idx = (L.t > sm.t_end - 60) & (L.t <= sm.t_end);
        if sum(idx) > 5
            s_std = std(L.unw(idx));
            if strcmp(sm.mode,'MODEL')
                idx_all = (L.t >= sm.t_start) & (L.t <= sm.t_end);
                travel = sum(abs(L.du(idx_all)));
                nmove  = sum(L.dN(idx_all) ~= 0);
                ntot   = sum(idx_all);
                fprintf("%-6s [MODEL] std=%.3f ns | 電圧移動量=%.4f V | LSB操作=%d/%d回\n", ...
                    sm.name, s_std, travel, nmove, ntot);
            else
                fprintf("%-6s [HOLD]  std=%.3f ns\n", sm.name, s_std);
            end
        end
    end

    %% === プロット ======================================================
    fig = figure('Name','model v1: FRFR & ao0','NumberTitle','off','Position',[80 80 950 560]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile;
    plot(L.t, L.unw, 'b-', 'LineWidth', 1.0); hold on;
    if ~isnan(target_adjusted)
        yline(target_adjusted, 'r--', sprintf('Target %.1f', target_adjusted));
    end
    for k = 1:numel(segmap)
        xline(segmap(k).t_start, 'k:');
        text(segmap(k).t_start, max(L.unw,[],'omitnan'), sprintf(' %s', segmap(k).name), ...
            'Rotation',90, 'VerticalAlignment','top', 'FontSize',8);
    end
    grid on; ylabel('FRFR (unwrapped) [ns]'); title('モデルベースFB v1: FRFR(上) と 制御電圧(下)');
    nexttile;
    plot(L.t, L.ao0*1e3, 'r-'); grid on;
    for k = 1:numel(segmap), xline(segmap(k).t_start, 'k:'); end
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(fig, sprintf('frfr_model_%s%s.pdf', ts, tag), 'ContentType','vector');

    %% === 結果 ==========================================================
    result = struct('log_csv',log_name, 'segmap_csv',seg_name, ...
        'target_adjusted',target_adjusted, 'segmap',segmap, ...
        'lsb_V',lsb_V, 't_run_start',t_run_start, 'opts',opts);
end

%% === ヘルパー =========================================================
function seg = mkseg(name, mode)
    seg = struct('name',name, 'mode',mode);
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
