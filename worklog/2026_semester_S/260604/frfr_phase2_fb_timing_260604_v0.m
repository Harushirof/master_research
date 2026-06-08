function result = frfr_phase2_fb_timing_260604_v0(opts)
%====================================================================
% Phase 2 コントローラ: 制御ループのサンプリングタイミング検証版
% (260526 v0 をベースに、タイミング起因の 0.6Hz ハンチングを潰す)
%
% 背景（260521 録音のヒルベルト解析より）:
%   FB 制御中（前半）は ±0.3〜0.4 ns の 0.6Hz うねりが発生し、
%   電圧固定の HOLD（後半 ±0.15 ns）より精度が悪い。
%   原因はFBが低周波位相揺れを注入していること。タイミング起因の
%   候補が以下の3つ。本スクリプトは各々を opts で切り替えて検証する。
%
%   ① freq_err を公称 Ts で割っている  → timing_mode='measured_dt'
%   ② ループ周期が非決定的             → timing_mode='fixed_period'
%   ③ 1ステップ1回読みでノイズが乗る   → n_oversample > 1
%
% 実験原則: 1 run につき 1 つだけ変える。残りは固定。
%   FB → HOLD の順で測り録音 → 同一 run の HOLD を基準に FB を評価。
%
%--------------------------------------------------------------------
% 使い方（opts は省略可。フィールド単位で上書き）:
%   % baseline（現状再現: 公称 Ts, 1回読み）
%   frfr_phase2_fb_timing_260604_v0();
%
%   % パターン1: 実測 dt で微分
%   o.timing_mode = 'measured_dt';            frfr_phase2_fb_timing_260604_v0(o);
%   % パターン2: ループ周期を一定化
%   o.timing_mode = 'fixed_period';           frfr_phase2_fb_timing_260604_v0(o);
%   % パターン3: Ts スイープ（本命）
%   o.timing_mode = 'fixed_period'; o.Ts = 1.0; o.run_tag = 'Ts1p0';
%   % パターン4: 多重読み中央値
%   o.n_oversample = 5;                       frfr_phase2_fb_timing_260604_v0(o);
%   % パターン5: 微分なし（積分のみ）
%   o.Kd = 0;        o.run_tag = 'Kd0';       frfr_phase2_fb_timing_260604_v0(o);
%
% opts フィールド（既定値）:
%   timing_mode : 'nominal' | 'measured_dt' | 'fixed_period'   ('nominal')
%                  nominal      : 公称 Ts で微分, pause(Ts)         （= 260526 v0 相当）
%                  measured_dt  : 実測 dt で微分, pause(Ts)
%                  fixed_period : 実測 dt で微分 + 周期を Ts に一定化
%   Ts          : サンプリング周期 [s]                         (0.3)
%   n_oversample: 1 ステップあたりのスコープ読み取り回数(中央値)  (1)
%   Ki          : 位相誤差の積分ゲイン [V/ns]                   (0.0003)
%   Kd          : 周波数誤差の減衰ゲイン [V/(ns/s)]             (0.0018)
%   FRFR_ref    : 目標 FRFR [ns]                               (25)
%   t_fb_end    : FB 制御終了時刻 [s]                          (300)
%   t_hold_end  : HOLD 終了時刻 [s]                            (600)
%   t_total     : 実験時間 [s]                                 (600)
%   du_max      : レートリミット [V/step]                      (0.05)
%   u_init      : ao0 初期値 [V]                               (1.54)
%   run_tag     : ファイル名に付与するタグ（パターン識別用）   ('')
%
% 出力 result:
%   .log_csv, .target_adjusted, .u_hold, .params
%   .fb_steady_state / .hold_state（区間統計）
%   .dt_stats（実ループ周期の平均/std/最大: タイミングジッタの直接指標）
%====================================================================

    %% === opts 既定値 ===================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct( ...
        'timing_mode', 'nominal', ...
        'Ts',           0.3, ...
        'n_oversample', 1, ...
        'Ki',           0.0003, ...
        'Kd',           0.0018, ...
        'FRFR_ref',     25, ...
        't_fb_end',     300, ...
        't_hold_end',   600, ...
        't_total',      600, ...
        'du_max',       0.05, ...
        'u_init',       1.54, ...
        'run_tag',      '');
    fn = fieldnames(def);
    for i = 1:numel(fn)
        if ~isfield(opts, fn{i}) || isempty(opts.(fn{i}))
            opts.(fn{i}) = def.(fn{i});
        end
    end

    valid_modes = {'nominal', 'measured_dt', 'fixed_period'};
    if ~any(strcmp(opts.timing_mode, valid_modes))
        error('timing_mode は %s のいずれかにしてください。', strjoin(valid_modes, ' / '));
    end
    if opts.t_fb_end > opts.t_hold_end
        error('t_fb_end (%.1f) は t_hold_end (%.1f) より小さく設定してください。', ...
            opts.t_fb_end, opts.t_hold_end);
    end
    if opts.t_hold_end > opts.t_total
        warning('t_hold_end (%.1f) > t_total (%.1f): OFF 区間が発生しません。', ...
            opts.t_hold_end, opts.t_total);
    end

    % ローカル変数へ展開
    timing_mode  = opts.timing_mode;
    Ts           = opts.Ts;
    n_oversample = max(1, round(opts.n_oversample));
    Ki           = opts.Ki;
    Kd           = opts.Kd;
    FRFR_ref     = opts.FRFR_ref;
    t_fb_end     = opts.t_fb_end;
    t_hold_end   = opts.t_hold_end;
    t_total      = opts.t_total;
    du_max       = opts.du_max;
    u_init       = opts.u_init;

    v_min = 0.0;
    v_max = 5.0;

    % アンラップ
    T_period    = 100;     % [ns] FRFR の周期（10MHz）
    JUMP_DETECT = 50;      % [ns] ジャンプ検出閾値
    OFFSET_STEP = 100;     % [ns] オフセット補正量

    %% === DAQ / Scope 初期化 ==========================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');   % ao0 のみ使用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    SAFE_AO0 = 0.0;
    c = onCleanup(@() cleanupDAQ(s, dev, SAFE_AO0)); %#ok<NASGU>

    %% === 状態変数 ======================================================
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_unwrapped = NaN;
    target_adjusted     = NaN;
    u_hold              = NaN;
    stage_prev          = "";
    t_prev              = NaN;   % 前ステップの時刻（実測 dt 用）

    %% === ログ配列 ======================================================
    time_log        = [];
    dt_actual_log   = [];   % 実ループ周期 [s]（タイミングジッタの直接指標）
    frfr_raw_log    = [];
    frfr_unwrap_log = [];
    e_phase_log     = [];
    freq_err_log    = [];
    delta_u_log     = [];
    ao0_log         = [];
    stage_log       = strings(0,1);

    %% === 初期出力 ======================================================
    u_applied = clamp(u_init, v_min, v_max);
    outputSingleScan(s, u_applied);

    fprintf("=== Phase 2 タイミング検証 (260604 v0) ===\n");
    fprintf("timing_mode = %s | Ts = %.2f s | n_oversample = %d\n", ...
        timing_mode, Ts, n_oversample);
    fprintf("Ki = %.4f, Kd = %.4f | 目標 FRFR = %.1f ns\n", Ki, Kd, FRFR_ref);
    fprintf("FB: 0〜%.0f s, HOLD: %.0f〜%.0f s, 計測: %.0f s\n", ...
        t_fb_end, t_fb_end, t_hold_end, t_total);
    if ~isempty(opts.run_tag), fprintf("run_tag = %s\n", opts.run_tag); end

    %% === メインループ ==================================================
    t_start = datetime('now');

    while true
        t_loop_top = datetime('now');
        t = seconds(t_loop_top - t_start);
        if t > t_total, break; end

        % ---- FRFR 読み取り（n_oversample 回の中央値）----
        raw_vals = nan(1, n_oversample);
        read_ok = true;
        for k = 1:n_oversample
            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                raw_vals(k) = str2double(readline(dev)) * 1e9;   % [ns]
            catch ME
                warning("FRFR read error: %s", ME.message);
                read_ok = false;
                break;
            end
        end
        if ~read_ok, break; end
        raw_frfr = median(raw_vals, 'omitnan');

        % ---- アンラップ ----
        if ~isnan(prev_raw_frfr)
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT
                frfr_offset = frfr_offset + OFFSET_STEP;
            elseif delta_raw >= +JUMP_DETECT
                frfr_offset = frfr_offset - OFFSET_STEP;
            end
        end
        frfr_unwrapped = raw_frfr + frfr_offset;
        prev_raw_frfr  = raw_frfr;

        % ---- 初回: 目標を最短距離に調整 ----
        if isnan(target_adjusted)
            remainder = mod(frfr_unwrapped - FRFR_ref, T_period);
            if remainder > T_period / 2
                remainder = remainder - T_period;
            end
            target_adjusted = frfr_unwrapped - remainder;
            fprintf("初期 FRFR = %.2f ns → 調整後目標 = %.2f ns\n", ...
                frfr_unwrapped, target_adjusted);
        end

        % ---- 位相誤差 ----
        e_phase = target_adjusted - frfr_unwrapped;

        % ---- 微分に使う時間刻み（timing_mode で切替）----
        %   nominal      : 公称 Ts（260526 v0 と同じ。タイミングずれを無視）
        %   measured_dt  : 実測 dt（前ステップからの実経過時間）
        %   fixed_period : 実測 dt（周期一定化と併用）
        dt_actual = t - t_prev;     % 実ループ周期（初回は NaN）
        if strcmp(timing_mode, 'nominal')
            dt_for_deriv = Ts;
        else
            if isnan(dt_actual) || dt_actual <= 0
                dt_for_deriv = Ts;          % 初回フォールバック
            else
                dt_for_deriv = dt_actual;
            end
        end

        % ---- 周波数誤差 ----
        if isnan(prev_frfr_unwrapped)
            freq_err = 0;
        else
            freq_err = (frfr_unwrapped - prev_frfr_unwrapped) / dt_for_deriv;
        end
        prev_frfr_unwrapped = frfr_unwrapped;
        t_prev = t;

        % ---- ステージ判定 & 制御則 -----------------------------------
        if t <= t_fb_end
            stage   = "FB";
            delta_u = Ki * e_phase - Kd * freq_err;
            delta_u = clamp(delta_u, -du_max, du_max);
            u_next  = clamp(u_applied + delta_u, v_min, v_max);
        elseif t <= t_hold_end
            stage = "HOLD";
            if isnan(u_hold)
                u_hold = u_applied;
                fprintf(">>> HOLD 突入 t=%.1f s: u_hold = %.4f V で固定\n", t, u_hold);
            end
            delta_u = 0;
            u_next  = u_hold;
        else
            stage = "OFF";
            if stage_prev ~= "OFF"
                fprintf(">>> OFF 突入 t=%.1f s: u = 0 V\n", t);
            end
            delta_u = 0;
            u_next  = 0;
        end
        stage_prev = stage;

        % ---- 出力 ----
        try
            outputSingleScan(s, u_next);
        catch ME
            warning("DAQ output error: %s", ME.message);
            break;
        end
        u_applied = u_next;

        % ---- ログ ----
        time_log(end+1)        = t;              %#ok<AGROW>
        dt_actual_log(end+1)   = dt_actual;      %#ok<AGROW>
        frfr_raw_log(end+1)    = raw_frfr;       %#ok<AGROW>
        frfr_unwrap_log(end+1) = frfr_unwrapped; %#ok<AGROW>
        e_phase_log(end+1)     = e_phase;        %#ok<AGROW>
        freq_err_log(end+1)    = freq_err;       %#ok<AGROW>
        delta_u_log(end+1)     = delta_u;        %#ok<AGROW>
        ao0_log(end+1)         = u_applied;      %#ok<AGROW>
        stage_log(end+1,1)     = stage;          %#ok<AGROW>

        fprintf("t=%6.1f [%s] dt=%.3f | FRFR=%.2f | e=%.2f | df=%.3f | du=%.5f | ao0=%.4f\n", ...
            t, stage, dt_actual, frfr_unwrapped, e_phase, freq_err, delta_u, u_applied);

        % ---- 待機（timing_mode で切替）------------------------------
        if strcmp(timing_mode, 'fixed_period')
            % ループ先頭からの所要時間を差し引き、周期を Ts に一定化
            used = seconds(datetime('now') - t_loop_top);
            pause(max(0.001, Ts - used));
        else
            pause(Ts);
        end
    end

    fprintf("=== タイミング検証 終了 ===\n");

    %% === CSV 保存 ======================================================
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag)
        tag = '';
    else
        tag = ['_' opts.run_tag];
    end
    log_name = sprintf('frfr_phase2_timing_%s_%s%s.csv', timing_mode, timestamp, tag);

    log_tbl = table( ...
        time_log(:), dt_actual_log(:), frfr_raw_log(:), frfr_unwrap_log(:), ...
        e_phase_log(:), freq_err_log(:), delta_u_log(:), ao0_log(:), stage_log(:), ...
        'VariableNames', { ...
            'time_s', 'dt_actual_s', 'frfr_raw_ns', 'frfr_unwrapped_ns', ...
            'e_phase_ns', 'freq_err_ns_per_s', 'delta_u_V', 'ao0_V', 'stage'});
    writetable(log_tbl, log_name);
    fprintf("ログ保存: %s\n", log_name);

    %% === プロット =======================================================
    fig1 = figure('Name', 'Phase 2 timing: FRFR', 'NumberTitle', 'off');
    plot(time_log, frfr_unwrap_log, 'b-', 'LineWidth', 1.2); hold on;
    yline(target_adjusted, 'r--', sprintf('Target %.1f ns', target_adjusted), 'LineWidth', 1.2);
    xline(t_fb_end, 'k:', 'FB→HOLD', 'LineWidth', 1.0);
    if t_hold_end < t_total, xline(t_hold_end, 'k:', 'HOLD→OFF', 'LineWidth', 1.0); end
    grid on; xlabel('Time [s]'); ylabel('FRFR (unwrapped) [ns]');
    title(sprintf('FRFR  (%s, Ts=%.2f, nOS=%d, Kd=%.4f)', timing_mode, Ts, n_oversample, Kd));
    exportgraphics(fig1, sprintf('frfr_phase2_timing_frfr_%s%s.pdf', timestamp, tag), 'ContentType', 'vector');

    fig2 = figure('Name', 'Phase 2 timing: dt_actual', 'NumberTitle', 'off');
    plot(time_log, dt_actual_log, '.-'); hold on;
    yline(Ts, 'r--', sprintf('Ts=%.2f', Ts));
    grid on; xlabel('Time [s]'); ylabel('actual loop period [s]');
    title('実ループ周期（タイミングジッタの直接指標）');
    exportgraphics(fig2, sprintf('frfr_phase2_timing_dt_%s%s.pdf', timestamp, tag), 'ContentType', 'vector');

    %% === 結果 ===========================================================
    result = struct();
    result.log_csv         = log_name;
    result.target_adjusted = target_adjusted;
    result.u_hold          = u_hold;
    result.params          = opts;

    % 実ループ周期の統計（タイミング修正の効きを数値で確認）
    dt_valid = dt_actual_log(~isnan(dt_actual_log));
    if ~isempty(dt_valid)
        result.dt_stats = struct('mean_s', mean(dt_valid), ...
            'std_s', std(dt_valid), 'max_s', max(dt_valid));
        fprintf("\n--- 実ループ周期 ---\n");
        fprintf("平均 %.4f s / std %.4f s / 最大 %.4f s (公称 Ts=%.2f)\n", ...
            mean(dt_valid), std(dt_valid), max(dt_valid), Ts);
    end

    % FB / HOLD 区間統計（各区間終了直前 60 秒）
    if numel(time_log) > 0
        idx_fb = (time_log > (t_fb_end - 60)) & (time_log <= t_fb_end);
        if sum(idx_fb) > 10
            result.fb_steady_state = struct( ...
                'mean_ns', mean(frfr_unwrap_log(idx_fb)), ...
                'std_ns',  std(frfr_unwrap_log(idx_fb)), ...
                'err_ns',  mean(e_phase_log(idx_fb)));
            fprintf("\n--- FB 終了直前 60 s ---\n");
            fprintf("FRFR 平均 %.3f ns (std %.3f ns), 位相誤差 %.3f ns\n", ...
                result.fb_steady_state.mean_ns, result.fb_steady_state.std_ns, ...
                result.fb_steady_state.err_ns);
        end
        idx_hold = (time_log > (t_hold_end - 60)) & (time_log <= t_hold_end);
        if sum(idx_hold) > 10
            result.hold_state = struct( ...
                'mean_ns', mean(frfr_unwrap_log(idx_hold)), ...
                'std_ns',  std(frfr_unwrap_log(idx_hold)), ...
                'u_hold',  u_hold);
            fprintf("\n--- HOLD 終了直前 60 s ---\n");
            fprintf("FRFR 平均 %.3f ns (std %.3f ns), u_hold %.4f V\n", ...
                result.hold_state.mean_ns, result.hold_state.std_ns, u_hold);
        end
    end
end

%% === ヘルパー関数 =====================================================
function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0)
    try, outputSingleScan(s, safe_ao0); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
