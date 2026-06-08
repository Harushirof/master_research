function result = frfr_phase2_fb_hold_260521_v2(t_total, FRFR_ref, t_fb_end, t_hold_end)
%====================================================================
% Phase 2 コントローラ: FRFR を指定値に収束させる (ao0 単独構成)
% + 2段階シーケンス（FB → HOLD）
%
%   Stage FB   : 0        〜 t_fb_end    ・・・ 通常の FB 制御
%   Stage HOLD : t_fb_end 〜 t_total     ・・・ FB 終端電圧で一定キープ
%
% デフォルト（260521 v2: 10 分計測, 5 分制御 + 5 分 HOLD）:
%   t_fb_end   = 300 s ( 5 分)
%   t_hold_end = 600 s (10 分: FB 5 分 + HOLD 5 分)
%   t_total    = 600 s (HOLD 終了 = 計測終了, OFF 区間なし)
%
% 制御則（FB 区間のみ、260512 版と同等）:
%   e_phase  = FRFR_ref - FRFR_unwrapped     [ns]
%   freq_err = dFRFR/dt                       [ns/s]
%   delta_u  = Ki * e_phase - Kd * freq_err   [V]
%   u[k]     = clamp(u[k-1] + delta_u, 0, 5) [V]
%
% プラントモデル: G(s) = K/s, K ≈ 81 ns/(V·s)
% 設計: 閉ループ極 z ≈ 0.924±0.039j, 整定時間 ≈ 15s
%
% 入力:
%   t_total    : 実験時間 [s]（デフォルト 600）
%   FRFR_ref   : 目標 FRFR [ns]（デフォルト 25）
%   t_fb_end   : FB 制御終了時刻 [s]（デフォルト 300）
%   t_hold_end : HOLD 終了時刻 [s]（デフォルト 600, t_total と同じなら OFF なし）
%
% 出力:
%   result.log_csv        : 保存した CSV ファイル名
%   result.target_adjusted: 自動調整後の目標 FRFR
%   result.u_hold         : HOLD 区間で保持した電圧
%   result.params         : 使用パラメータ一覧
%====================================================================

    if nargin < 1 || isempty(t_total),    t_total    = 600; end
    if nargin < 2 || isempty(FRFR_ref),   FRFR_ref   = 25;  end
    if nargin < 3 || isempty(t_fb_end),   t_fb_end   = 300; end
    if nargin < 4 || isempty(t_hold_end), t_hold_end = 600; end

    if t_fb_end > t_hold_end
        error('t_fb_end (%.1f) は t_hold_end (%.1f) より小さく設定してください。', ...
            t_fb_end, t_hold_end);
    end
    if t_hold_end > t_total
        warning('t_hold_end (%.1f) > t_total (%.1f): OFF 区間が発生しません。', ...
            t_hold_end, t_total);
    end

    %% === DAQ / Scope 初期化 ==========================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');   % ao0 のみ使用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    SAFE_AO0 = 0.0;
    c = onCleanup(@() cleanupDAQ(s, dev, SAFE_AO0)); %#ok<NASGU>

    %% === 制御パラメータ ================================================
    Ts = 0.3;               % [s] サンプリング周期

    u_init = 1.54;          % [V] ao0 初期値（5/12 動作点確認済み）

    % 電圧制限
    v_min = 0.0;
    v_max = 5.0;

    % --- Phase 2 ゲイン ---
    % プラント: K ≈ 81 ns/(V·s), b = K*Ts = 24.3 ns/V
    % 設計: omega_n = 0.3 rad/s, zeta = 0.8
    Ki = 0.0003;            % [V/ns]     位相誤差の積分ゲイン
    Kd = 0.0018;            % [V/(ns/s)] 周波数誤差の減衰ゲイン

    % --- レートリミット ---
    du_max = 0.05;          % [V/step] 急激な電圧変化を防止

    % --- アンラップ ---
    T_period     = 100;     % [ns] FRFR の周期（10MHz）
    JUMP_DETECT  = 50;      % [ns] ジャンプ検出閾値
    OFFSET_STEP  = 100;     % [ns] オフセット補正量

    %% === 状態変数 ======================================================
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_unwrapped = NaN;
    target_adjusted     = NaN;

    u_hold       = NaN;     % HOLD 突入時にキャプチャ
    stage_prev   = "";      % ステージ遷移ログ用

    %% === ログ配列 ======================================================
    time_log         = [];
    frfr_raw_log     = [];
    frfr_unwrap_log  = [];
    e_phase_log      = [];
    freq_err_log     = [];
    delta_u_log      = [];
    ao0_log          = [];
    stage_log        = strings(0,1);

    %% === 初期出力 ======================================================
    u_applied = clamp(u_init, v_min, v_max);
    outputSingleScan(s, u_applied);

    fprintf("=== Phase 2 FB+HOLD 開始 (ao0 単独, 260521 v2) ===\n");
    fprintf("目標 FRFR = %.1f ns, 実験時間 = %.0f s\n", FRFR_ref, t_total);
    fprintf("Stage FB  : 0     〜 %.0f s\n", t_fb_end);
    fprintf("Stage HOLD: %.0f 〜 %.0f s\n", t_fb_end, t_hold_end);
    if t_hold_end < t_total
        fprintf("Stage OFF : %.0f 〜 %.0f s\n", t_hold_end, t_total);
    end
    fprintf("Ki = %.4f, Kd = %.4f, Ts = %.1f s, ao0 初期 = %.3f V\n", ...
        Ki, Kd, Ts, u_applied);

    %% === メインループ ==================================================
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > t_total, break; end

        % ---- FRFR 読み取り ----
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        raw_frfr = frfr_sec * 1e9;

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
        prev_raw_frfr = raw_frfr;

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

        % ---- 周波数誤差 ----
        if isnan(prev_frfr_unwrapped)
            freq_err = 0;
        else
            freq_err = (frfr_unwrapped - prev_frfr_unwrapped) / Ts;
        end
        prev_frfr_unwrapped = frfr_unwrapped;

        % ---- ステージ判定 & 制御則 -----------------------------------
        if t <= t_fb_end
            % Stage FB: 通常の FB 制御
            stage   = "FB";
            delta_u = Ki * e_phase - Kd * freq_err;
            delta_u = clamp(delta_u, -du_max, du_max);
            u_next  = clamp(u_applied + delta_u, v_min, v_max);

        elseif t <= t_hold_end
            % Stage HOLD: FB 終端の電圧で一定キープ
            stage = "HOLD";
            if isnan(u_hold)
                u_hold = u_applied;     % FB 区間の最後の出力をキャプチャ
                fprintf(">>> HOLD 突入 t=%.1f s: u_hold = %.4f V で固定\n", ...
                    t, u_hold);
            end
            delta_u = 0;
            u_next  = u_hold;

        else
            % Stage OFF: 出力 0 V
            stage   = "OFF";
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
        time_log(end+1)         = t;                  %#ok<AGROW>
        frfr_raw_log(end+1)     = raw_frfr;           %#ok<AGROW>
        frfr_unwrap_log(end+1)  = frfr_unwrapped;     %#ok<AGROW>
        e_phase_log(end+1)      = e_phase;             %#ok<AGROW>
        freq_err_log(end+1)     = freq_err;            %#ok<AGROW>
        delta_u_log(end+1)      = delta_u;             %#ok<AGROW>
        ao0_log(end+1)          = u_applied;           %#ok<AGROW>
        stage_log(end+1,1)      = stage;               %#ok<AGROW>

        fprintf("t=%6.1f [%s] | FRFR=%.2f ns | e=%.2f ns | df=%.3f ns/s | du=%.5f | ao0=%.4f V\n", ...
            t, stage, frfr_unwrapped, e_phase, freq_err, delta_u, u_applied);

        pause(Ts);
    end

    fprintf("=== Phase 2 FB+HOLD 終了 ===\n");

    %% === CSV 保存 ======================================================
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    log_name = sprintf('frfr_phase2_fb_hold_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), frfr_raw_log(:), frfr_unwrap_log(:), ...
        e_phase_log(:), freq_err_log(:), delta_u_log(:), ao0_log(:), ...
        stage_log(:), ...
        'VariableNames', { ...
            'time_s', 'frfr_raw_ns', 'frfr_unwrapped_ns', ...
            'e_phase_ns', 'freq_err_ns_per_s', 'delta_u_V', 'ao0_V', 'stage'});

    writetable(log_tbl, log_name);
    fprintf("ログ保存: %s\n", log_name);

    %% === プロット =======================================================
    fig1 = figure('Name', 'Phase 2: FRFR vs Time', 'NumberTitle', 'off');
    plot(time_log, frfr_unwrap_log, 'b-', 'LineWidth', 1.5); hold on;
    yline(target_adjusted, 'r--', sprintf('Target %.1f ns', target_adjusted), 'LineWidth', 1.5);
    xline(t_fb_end,   'k:', 'FB→HOLD', 'LineWidth', 1.2);
    if t_hold_end < t_total
        xline(t_hold_end, 'k:', 'HOLD→OFF', 'LineWidth', 1.2);
    end
    grid on; xlabel('Time [s]'); ylabel('FRFR (unwrapped) [ns]');
    title('Phase 2: FRFR (FB / HOLD)');
    exportgraphics(fig1, sprintf('frfr_phase2_hold_frfr_%s.pdf', timestamp), 'ContentType', 'vector');

    fig2 = figure('Name', 'Phase 2: Phase Error', 'NumberTitle', 'off');
    plot(time_log, e_phase_log, 'LineWidth', 1.5); hold on;
    yline(0, 'r--', 'Zero Error');
    xline(t_fb_end,   'k:', 'FB→HOLD', 'LineWidth', 1.2);
    if t_hold_end < t_total
        xline(t_hold_end, 'k:', 'HOLD→OFF', 'LineWidth', 1.2);
    end
    grid on; xlabel('Time [s]'); ylabel('Phase Error [ns]');
    title('Phase 2: Phase Error (FB / HOLD)');
    exportgraphics(fig2, sprintf('frfr_phase2_hold_error_%s.pdf', timestamp), 'ContentType', 'vector');

    fig3 = figure('Name', 'Phase 2: Control Voltage', 'NumberTitle', 'off');
    plot(time_log, ao0_log, 'LineWidth', 1.5); hold on;
    xline(t_fb_end,   'k:', 'FB→HOLD', 'LineWidth', 1.2);
    if t_hold_end < t_total
        xline(t_hold_end, 'k:', 'HOLD→OFF', 'LineWidth', 1.2);
    end
    grid on; xlabel('Time [s]'); ylabel('ao0 [V]');
    title('Phase 2: Control Voltage (FB / HOLD)');
    exportgraphics(fig3, sprintf('frfr_phase2_hold_ao0_%s.pdf', timestamp), 'ContentType', 'vector');

    %% === 結果 ===========================================================
    result = struct();
    result.log_csv = log_name;
    result.target_adjusted = target_adjusted;
    result.u_hold = u_hold;
    result.params = struct( ...
        'Ts', Ts, 't_total', t_total, 'FRFR_ref', FRFR_ref, ...
        't_fb_end', t_fb_end, 't_hold_end', t_hold_end, ...
        'Ki', Ki, 'Kd', Kd, 'du_max', du_max, ...
        'u_init', u_init, 'v_min', v_min, 'v_max', v_max, ...
        'T_period', T_period, 'JUMP_DETECT', JUMP_DETECT, ...
        'OFFSET_STEP', OFFSET_STEP, 'ip', ip);

    % FB 区間の定常状態統計（FB 終了直前 60 秒）
    if numel(time_log) > 0
        idx_fb_ss = (time_log > (t_fb_end - 60)) & (time_log <= t_fb_end);
        if sum(idx_fb_ss) > 10
            ss_mean = mean(frfr_unwrap_log(idx_fb_ss));
            ss_std  = std(frfr_unwrap_log(idx_fb_ss));
            ss_err  = mean(e_phase_log(idx_fb_ss));
            fprintf("\n--- FB 終了直前 60 秒 ---\n");
            fprintf("FRFR 平均: %.3f ns (std: %.3f ns)\n", ss_mean, ss_std);
            fprintf("位相誤差 平均: %.3f ns\n", ss_err);
            fprintf("目標: %.2f ns\n", target_adjusted);
            result.fb_steady_state = struct('mean_ns', ss_mean, 'std_ns', ss_std, 'err_ns', ss_err);
        end

        % HOLD 区間の挙動（HOLD 終了直前 60 秒）
        idx_hold_ss = (time_log > (t_hold_end - 60)) & (time_log <= t_hold_end);
        if sum(idx_hold_ss) > 10
            h_mean = mean(frfr_unwrap_log(idx_hold_ss));
            h_std  = std(frfr_unwrap_log(idx_hold_ss));
            fprintf("\n--- HOLD 終了直前 60 秒 ---\n");
            fprintf("FRFR 平均: %.3f ns (std: %.3f ns)\n", h_mean, h_std);
            fprintf("保持電圧 u_hold: %.4f V\n", u_hold);
            result.hold_state = struct('mean_ns', h_mean, 'std_ns', h_std, 'u_hold', u_hold);
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
