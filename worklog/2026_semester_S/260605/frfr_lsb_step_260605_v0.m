function result = frfr_lsb_step_260605_v0(opts)
%====================================================================
% FRFR の最小電圧ステップ応答測定 (260605 v0)
%
%   目的: HOLD(電圧固定)を基準に、制御電圧を DAC 最小単位(1 LSB)ずつ
%   階段状に上げたとき、FRFR がどれだけ変化するか(=最小分解能での
%   プラントゲイン)を測る。
%
%   シーケンス:
%     Phase LOCK : FB制御で目標FRFRに一度ロック (t_lock秒)。
%                  ロック電圧 u_lock = 終端の電圧中央値。
%     Phase STAIR: u_lock から +1LSB ずつ、step_dwell秒ごとに n_steps段。
%                  各段で FRFR を Ts間隔で読み記録(制御はしない)。
%                  既定 30段 × 10s = 300s。
%
%   評価: 各段の10s窓で FRFR(unwrapped) を直線フィット → 傾き[ns/s]。
%         傾き vs 段数 の直線フィット傾き = 1ステップ(1LSB)あたりの
%         FRFR傾き変化 = K * LSB。これと K[ns/(V*s)] を出力。
%
%   1 LSB = dac_range_V / 2^dac_bits = 20/65536 ≒ 305 µV (USB-6211, ±10V/16bit)
%
%   使い方(Current Folder を 260605 に):
%     frfr_lsb_step_260605_v0();
%   動作確認(短縮): o.t_lock=20; o.n_steps=6; frfr_lsb_step_260605_v0(o);
%
%   opts(既定): t_lock(60) n_steps(30) step_dwell_s(10) n_lsb(1)
%               settle_s(1.5) FRFR_ref(25) u_init(1.54)
%               Ki(0.0003) Kd(0.0018) du_max(0.05) Ts(0.3)
%               dac_range_V(20) dac_bits(16) run_tag('')
%====================================================================

    %% === opts ==========================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct('t_lock',60, 'n_steps',30, 'step_dwell_s',10, 'n_lsb',1, ...
                 'settle_s',1.5, 'FRFR_ref',25, 'u_init',1.54, ...
                 'Ki',0.0003, 'Kd',0.0018, 'du_max',0.05, 'Ts',0.3, ...
                 'dac_range_V',20, 'dac_bits',16, 'run_tag','');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i})), opts.(fn{i}) = def.(fn{i}); end
    end
    Ts = opts.Ts;  Ki = opts.Ki;  Kd = opts.Kd;
    lsb_V = opts.dac_range_V / 2^opts.dac_bits;     % 1 LSB [V]
    dV    = opts.n_lsb * lsb_V;                     % 1ステップの電圧増分 [V]

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

    %% === 状態 ==========================================================
    prev_raw = NaN; frfr_off = 0; prev_unw = NaN; target = NaN;
    u_applied = clamp(opts.u_init, v_min, v_max);
    outputSingleScan(s, u_applied);

    % ログ
    L = struct('t',[], 'phase',strings(0,1), 'level',[], 'ao0',[], ...
               'raw',[], 'unw',[]);

    fprintf("=== FRFR 最小ステップ応答 (260605 v0) ===\n");
    fprintf("1 LSB = %.6g V (%.1f µV) | 1ステップ = %d LSB = %.6g V\n", ...
        lsb_V, lsb_V*1e6, opts.n_lsb, dV);
    fprintf("LOCK %.0fs → STAIR %d段 × %.0fs = %.0fs\n", ...
        opts.t_lock, opts.n_steps, opts.step_dwell_s, opts.n_steps*opts.step_dwell_s);

    t_run = datetime('now');

    %% === Phase LOCK (FB制御) ==========================================
    fprintf("\n--- Phase LOCK (FB) ---\n");
    lock_u = [];  lock_t = [];
    while true
        t = seconds(datetime('now') - t_run);
        if t > opts.t_lock, break; end
        [raw_frfr, ok] = read_frfr(dev); if ~ok, break; end
        [unw, frfr_off, prev_raw] = do_unwrap(raw_frfr, prev_raw, frfr_off, JUMP_DETECT, OFFSET_STEP);

        if isnan(target)
            r = mod(unw - opts.FRFR_ref, T_period);
            if r > T_period/2, r = r - T_period; end
            target = unw - r;
            fprintf("初期 FRFR=%.2f → 目標=%.2f ns\n", unw, target);
        end
        e = target - unw;
        if isnan(prev_unw), df = 0; else, df = (unw - prev_unw)/Ts; end
        prev_unw = unw;

        du = clamp(Ki*e - Kd*df, -opts.du_max, opts.du_max);
        u_applied = clamp(u_applied + du, v_min, v_max);
        outputSingleScan(s, u_applied);

        L.t(end+1)=t; L.phase(end+1,1)="lock"; L.level(end+1)=NaN; %#ok<AGROW>
        L.ao0(end+1)=u_applied; L.raw(end+1)=raw_frfr; L.unw(end+1)=unw; %#ok<AGROW>
        lock_u(end+1)=u_applied; lock_t(end+1)=t; %#ok<AGROW>
        pause(Ts);
    end

    % ロック電圧 = 終端 min(10s,半分) の中央値
    if isempty(lock_u), error("LOCK 区間でデータが取れませんでした。"); end
    tail = lock_t > (max(lock_t) - min(10, opts.t_lock/2));
    u_lock = median(lock_u(tail));
    fprintf(">>> u_lock = %.5f V (終端中央値)\n", u_lock);

    %% === Phase STAIR (開ループ階段) ===================================
    fprintf("\n--- Phase STAIR (開ループ +%dLSBずつ) ---\n", opts.n_lsb);
    for k = 0:(opts.n_steps-1)
        u_k = clamp(u_lock + k*dV, v_min, v_max);
        outputSingleScan(s, u_k);
        u_applied = u_k;
        seg_t0 = seconds(datetime('now') - t_run);
        started = false;
        while true
            t = seconds(datetime('now') - t_run);
            if started && (t - seg_t0 > opts.step_dwell_s), break; end
            started = true;
            [raw_frfr, ok] = read_frfr(dev); if ~ok, break; end
            [unw, frfr_off, prev_raw] = do_unwrap(raw_frfr, prev_raw, frfr_off, JUMP_DETECT, OFFSET_STEP);
            prev_unw = unw;

            L.t(end+1)=t; L.phase(end+1,1)="stair"; L.level(end+1)=k; %#ok<AGROW>
            L.ao0(end+1)=u_k; L.raw(end+1)=raw_frfr; L.unw(end+1)=unw; %#ok<AGROW>
            pause(Ts);
        end
        fprintf("段 %2d/%d: ao0=%.5f V (ΔV=%+.4f mV) FRFR=%.2f ns\n", ...
            k, opts.n_steps-1, u_k, (u_k-u_lock)*1e3, unw);
    end
    fprintf("=== 測定終了 ===\n");

    %% === 保存 ==========================================================
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag=''; else, tag=['_' opts.run_tag]; end
    csv = sprintf('frfr_lsb_step_%s%s.csv', ts, tag);
    writetable(table(L.t(:),L.phase(:),L.level(:),L.ao0(:),L.raw(:),L.unw(:), ...
        'VariableNames',{'time_s','phase','level_k','ao0_V','frfr_raw_ns','frfr_unwrapped_ns'}), csv);
    fprintf("ログ保存: %s\n", csv);

    %% === 各段の傾き(slope)を直線フィット =============================
    levels = 0:(opts.n_steps-1);
    slope = nan(1, opts.n_steps);   % [ns/s]
    dV_lvl = levels * dV;           % 基準からの電圧増分 [V]
    for k = levels
        idx = (L.phase=="stair") & (L.level==k);
        tk = L.t(idx); yk = L.unw(idx);
        % 各段の頭 settle_s を除いてフィット(ステップ整定を避ける)
        keep = tk > (min(tk) + opts.settle_s);
        if sum(keep) >= 3
            p = polyfit(tk(keep), yk(keep), 1);
            slope(k+1) = p(1);
        end
    end

    % 傾き vs 段数 の直線フィット → 1ステップあたりの傾き変化
    good = ~isnan(slope);
    pslope = polyfit(levels(good), slope(good), 1);
    slope_per_step = pslope(1);          % [ns/s] / step
    K_est = slope_per_step / dV;         % [ns/(V*s)]
    dphase_per_step = slope_per_step * opts.step_dwell_s; % 各窓での寄与 [ns/step]

    fprintf("\n===== 結果 =====\n");
    fprintf("1ステップ(=%d LSB, %.4f mV)あたり:\n", opts.n_lsb, dV*1e3);
    fprintf("  FRFR傾きの変化   = %.4g ns/s /step\n", slope_per_step);
    fprintf("  → 10s窓での寄与  = %.4g ns /step\n", dphase_per_step);
    fprintf("推定プラントゲイン K = %.3g ns/(V*s)\n", K_est);
    fprintf("(参考: 1 LSB=%.1f µV)\n", lsb_V*1e6);

    %% === プロット ======================================================
    % 図1: FRFR と 電圧の時系列
    f1 = figure('Name','LSB step: FRFR & ao0','NumberTitle','off','Position',[80 80 900 480]);
    tl = tiledlayout(2,1,'TileSpacing','compact');
    nexttile; plot(L.t, L.unw, 'b-'); grid on; ylabel('FRFR unwrapped [ns]');
    title('最小ステップ応答: FRFR(上) と 制御電圧(下)');
    xline(opts.t_lock,'k:','LOCK→STAIR');
    nexttile; plot(L.t, L.ao0*1e3, 'r-'); grid on;
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(f1, sprintf('frfr_lsb_step_ts_%s%s.png', ts, tag), 'Resolution',300);

    % 図2: 段ごとの傾き vs 電圧増分(主結果)
    f2 = figure('Name','LSB step: slope vs dV','NumberTitle','off','Position',[100 100 720 460]);
    plot(dV_lvl*1e3, slope, 'o-'); hold on;
    plot(dV_lvl*1e3, polyval(pslope, levels), 'r--');
    grid on; xlabel('電圧増分 ΔV (u\_lock 基準) [mV]'); ylabel('FRFR傾き [ns/s]');
    title(sprintf('1ステップ(%dLSB,%.3fmV)あたり傾き変化 %.3g ns/s, K≈%.3g ns/(V·s)', ...
        opts.n_lsb, dV*1e3, slope_per_step, K_est));
    exportgraphics(f2, sprintf('frfr_lsb_step_slope_%s%s.png', ts, tag), 'Resolution',300);

    %% === 結果構造体 ===================================================
    result = struct('csv',csv, 'u_lock',u_lock, 'lsb_V',lsb_V, 'dV',dV, ...
        'levels',levels, 'slope_ns_per_s',slope, 'dV_lvl_V',dV_lvl, ...
        'slope_per_step',slope_per_step, 'dphase_per_step',dphase_per_step, ...
        'K_est',K_est, 'opts',opts);
end

%% === ローカル関数 =====================================================
function [raw_ns, ok] = read_frfr(dev)
    ok = true; raw_ns = NaN;
    try
        writeline(dev, "MEAS:ADV:P3:VAL?");
        raw_ns = str2double(readline(dev)) * 1e9;
    catch ME
        warning("FRFR read error: %s", ME.message); ok = false;
    end
end

function [unw, frfr_off, prev_raw] = do_unwrap(raw, prev_raw, frfr_off, JUMP, STEP)
    if ~isnan(prev_raw)
        d = raw - prev_raw;
        if     d <= -JUMP, frfr_off = frfr_off + STEP;
        elseif d >= +JUMP, frfr_off = frfr_off - STEP; end
    end
    unw = raw + frfr_off;
    prev_raw = raw;
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
