function result = frfr_phase2_fb_timing_260604_v1(opts)
%====================================================================
% Phase 2 コントローラ v1
% (v0 = タイミング検証 をベースに、「電圧をいじること自体が位相を
%  ずらす」対策を追加。狙い = ロックを保てる範囲で電圧変化を最小化)
%
% v0 からの追加:
%   ・deadband_ns : 位相ズレがこの範囲内なら電圧を変えない（突かない）
%   ・delta_u 統計 : FB 区間で電圧をどれだけ動かしたか（合計移動量・回数）
%                    を出力。ジッタと併せて「動かす量 vs 精度」を比較する。
%
% 当日のラン（各2回, 10分 = FB5分 + HOLD5分, 録音WAV + CSV）:
%   frfr_phase2_fb_timing_260604_v1();                                   % 基準
%   o=struct('Ts',1.0,'run_tag','slow');           ...v1(o);             % #3 ゆっくり
%   o=struct('n_oversample',5,'run_tag','avg');     ...v1(o);            % #4 平均
%   o=struct('Ts',1.0,'n_oversample',5,'deadband_ns',0.5,'du_max',0.01,'run_tag','gentle'); % 仕上げ
%
% opts フィールド（既定値）:
%   timing_mode : 'nominal'|'measured_dt'|'fixed_period'  ('measured_dt')
%   Ts          : サンプリング周期 [s]                    (0.3)
%   n_oversample: 1ステップのスコープ読み回数(中央値)      (1)
%   deadband_ns : この範囲内なら電圧を変えない [ns]        (0 = 無効)
%   du_max      : 1ステップの電圧変化上限 [V/step]         (0.05)
%   Ki, Kd      : 位相/周波数ゲイン                        (0.0003 / 0.0018)
%   FRFR_ref    : 目標 FRFR [ns]                           (25)
%   t_fb_end / t_hold_end / t_total : 区間 [s]             (300 / 600 / 600)
%   u_init      : ao0 初期値 [V]                           (1.54)
%   run_tag     : ファイル名タグ                           ('')
%
% 出力 result: .log_csv .target_adjusted .u_hold .params
%   .dt_stats（実周期）.fb_steady_state .hold_state
%   .du_stats（FB区間: 合計移動量[V] / 変化回数 / 平均|delta_u|）
%====================================================================

    %% === opts 既定値 ===================================================
    if nargin < 1 || isempty(opts), opts = struct(); end
    def = struct( ...
        'timing_mode', 'measured_dt', ...
        'Ts',           0.3, ...
        'n_oversample', 1, ...
        'deadband_ns',  0, ...
        'du_max',       0.05, ...
        'Ki',           0.0003, ...
        'Kd',           0.0018, ...
        'FRFR_ref',     25, ...
        't_fb_end',     300, ...
        't_hold_end',   600, ...
        't_total',      600, ...
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
        error('t_fb_end (%.1f) は t_hold_end (%.1f) より小さく。', opts.t_fb_end, opts.t_hold_end);
    end

    timing_mode  = opts.timing_mode;
    Ts           = opts.Ts;
    n_oversample = max(1, round(opts.n_oversample));
    deadband_ns  = opts.deadband_ns;
    du_max       = opts.du_max;
    Ki           = opts.Ki;
    Kd           = opts.Kd;
    FRFR_ref     = opts.FRFR_ref;
    t_fb_end     = opts.t_fb_end;
    t_hold_end   = opts.t_hold_end;
    t_total      = opts.t_total;
    u_init       = opts.u_init;

    v_min = 0.0;  v_max = 5.0;
    T_period    = 100;     % [ns] FRFR の周期（10MHz）
    JUMP_DETECT = 50;      % [ns] ジャンプ検出閾値
    OFFSET_STEP = 100;     % [ns] オフセット補正量

    %% === DAQ / Scope 初期化 ==========================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

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
    t_prev              = NaN;

    %% === ログ配列 ======================================================
    time_log        = [];
    dt_actual_log   = [];
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

    fprintf("=== Phase 2 v1 (電圧変化最小化) ===\n");
    fprintf("timing=%s | Ts=%.2f | nOS=%d | deadband=%.2f ns | du_max=%.3f V\n", ...
        timing_mode, Ts, n_oversample, deadband_ns, du_max);
    fprintf("Ki=%.4f Kd=%.4f | 目標 %.1f ns | FB 0-%.0f / HOLD %.0f-%.0f s\n", ...
        Ki, Kd, FRFR_ref, t_fb_end, t_fb_end, t_hold_end);
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
                raw_vals(k) = str2double(readline(dev)) * 1e9;
            catch ME
                warning("FRFR read error: %s", ME.message);
                read_ok = false; break;
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
            if remainder > T_period / 2, remainder = remainder - T_period; end
            target_adjusted = frfr_unwrapped - remainder;
            fprintf("初期 FRFR = %.2f ns → 調整後目標 = %.2f ns\n", frfr_unwrapped, target_adjusted);
        end

        % ---- 位相誤差 ----
        e_phase = target_adjusted - frfr_unwrapped;

        % ---- 微分に使う時間刻み ----
        dt_actual = t - t_prev;
        if strcmp(timing_mode, 'nominal')
            dt_for_deriv = Ts;
        elseif isnan(dt_actual) || dt_actual <= 0
            dt_for_deriv = Ts;
        else
            dt_for_deriv = dt_actual;
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
            stage = "FB";
            % デッドバンド: 位相ズレが小さいうちは電圧を変えない（突かない）
            if abs(e_phase) <= deadband_ns
                delta_u = 0;
            else
                delta_u = Ki * e_phase - Kd * freq_err;
                delta_u = clamp(delta_u, -du_max, du_max);
            end
            u_next = clamp(u_applied + delta_u, v_min, v_max);

        elseif t <= t_hold_end
            stage = "HOLD";
            if isnan(u_hold)
                u_hold = u_applied;
                fprintf(">>> HOLD 突入 t=%.1f s: u_hold = %.4f V で固定\n", t, u_hold);
            end
            delta_u = 0;  u_next = u_hold;

        else
            stage = "OFF";
            if stage_prev ~= "OFF", fprintf(">>> OFF 突入 t=%.1f s\n", t); end
            delta_u = 0;  u_next = 0;
        end
        stage_prev = stage;

        % ---- 出力 ----
        try
            outputSingleScan(s, u_next);
        catch ME
            warning("DAQ output error: %s", ME.message); break;
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

        % ---- 待機 ----
        if strcmp(timing_mode, 'fixed_period')
            used = seconds(datetime('now') - t_loop_top);
            pause(max(0.001, Ts - used));
        else
            pause(Ts);
        end
    end
    fprintf("=== v1 終了 ===\n");

    %% === CSV 保存 ======================================================
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    if isempty(opts.run_tag), tag = ''; else, tag = ['_' opts.run_tag]; end
    log_name = sprintf('frfr_phase2_v1_%s%s.csv', timestamp, tag);

    log_tbl = table( ...
        time_log(:), dt_actual_log(:), frfr_raw_log(:), frfr_unwrap_log(:), ...
        e_phase_log(:), freq_err_log(:), delta_u_log(:), ao0_log(:), stage_log(:), ...
        'VariableNames', {'time_s','dt_actual_s','frfr_raw_ns','frfr_unwrapped_ns', ...
            'e_phase_ns','freq_err_ns_per_s','delta_u_V','ao0_V','stage'});
    writetable(log_tbl, log_name);
    fprintf("ログ保存: %s\n", log_name);

    %% === プロット =======================================================
    fig1 = figure('Name','v1: FRFR','NumberTitle','off');
    plot(time_log, frfr_unwrap_log, 'b-', 'LineWidth', 1.2); hold on;
    yline(target_adjusted, 'r--', sprintf('Target %.1f ns', target_adjusted));
    xline(t_fb_end, 'k:', 'FB→HOLD');
    if t_hold_end < t_total, xline(t_hold_end, 'k:', 'HOLD→OFF'); end
    grid on; xlabel('Time [s]'); ylabel('FRFR (unwrapped) [ns]');
    title(sprintf('FRFR (Ts=%.2f nOS=%d db=%.2f du=%.3f)', Ts, n_oversample, deadband_ns, du_max));
    exportgraphics(fig1, sprintf('frfr_phase2_v1_frfr_%s%s.pdf', timestamp, tag), 'ContentType','vector');

    fig2 = figure('Name','v1: ao0','NumberTitle','off');
    plot(time_log, ao0_log, 'LineWidth', 1.2); hold on;
    xline(t_fb_end, 'k:', 'FB→HOLD');
    grid on; xlabel('Time [s]'); ylabel('ao0 [V]');
    title('制御電圧（FB でどれだけ動かしたか）');
    exportgraphics(fig2, sprintf('frfr_phase2_v1_ao0_%s%s.pdf', timestamp, tag), 'ContentType','vector');

    %% === 結果 ===========================================================
    result = struct();
    result.log_csv = log_name;
    result.target_adjusted = target_adjusted;
    result.u_hold = u_hold;
    result.params = opts;

    dt_valid = dt_actual_log(~isnan(dt_actual_log));
    if ~isempty(dt_valid)
        result.dt_stats = struct('mean_s',mean(dt_valid),'std_s',std(dt_valid),'max_s',max(dt_valid));
        fprintf("\n--- 実ループ周期 --- 平均 %.4f / std %.4f / 最大 %.4f s\n", ...
            mean(dt_valid), std(dt_valid), max(dt_valid));
    end

    if numel(time_log) > 0
        % FB 区間の電圧移動量（電圧をどれだけ・何回いじったか）
        idx_fb_all = (time_log <= t_fb_end);
        du_fb = delta_u_log(idx_fb_all);
        result.du_stats = struct( ...
            'total_travel_V', sum(abs(du_fb)), ...
            'n_changes',      sum(abs(du_fb) > 1e-9), ...
            'mean_abs_du_V',  mean(abs(du_fb)));
        fprintf("\n--- FB 区間の電圧変化 ---\n");
        fprintf("合計移動量 %.4f V / 変化回数 %d / 平均|du| %.5f V\n", ...
            result.du_stats.total_travel_V, result.du_stats.n_changes, result.du_stats.mean_abs_du_V);

        % FB / HOLD 区間統計（各区間終了直前 60 秒）
        idx_fb = (time_log > (t_fb_end - 60)) & (time_log <= t_fb_end);
        if sum(idx_fb) > 10
            result.fb_steady_state = struct('mean_ns',mean(frfr_unwrap_log(idx_fb)), ...
                'std_ns',std(frfr_unwrap_log(idx_fb)),'err_ns',mean(e_phase_log(idx_fb)));
            fprintf("\n--- FB 終了直前 60s --- FRFR %.3f ns (std %.3f), 誤差 %.3f ns\n", ...
                result.fb_steady_state.mean_ns, result.fb_steady_state.std_ns, result.fb_steady_state.err_ns);
        end
        idx_hold = (time_log > (t_hold_end - 60)) & (time_log <= t_hold_end);
        if sum(idx_hold) > 10
            result.hold_state = struct('mean_ns',mean(frfr_unwrap_log(idx_hold)), ...
                'std_ns',std(frfr_unwrap_log(idx_hold)),'u_hold',u_hold);
            fprintf("--- HOLD 終了直前 60s --- FRFR %.3f ns (std %.3f), u_hold %.4f V\n", ...
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
