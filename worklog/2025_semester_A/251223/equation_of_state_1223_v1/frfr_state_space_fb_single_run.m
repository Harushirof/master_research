%2025/12/16と同じもの
function result = frfr_state_space_fb_single_run(t_total)
%====================================================================
% 一次系に戻したFB（電圧を積分更新しない）
%
% 物理：FRFRは(電圧→周波数差)を1回積分した量
% 制御：u_k = u0 - K * e_k  （uを内部状態として蓄積しない）
%
% - FRFR target: 25 ns
% - Ts = 0.3 s
% - アンラップ: ユーザー提示ロジックをそのまま使用（正）
%
% 出力:
%   result.log_csv : 保存ログCSV名
%   result.params  : 使用パラメータ
%
% ログCSV列:
%   time_s, frfr_ns, err_ns, ao1_V, u_cmd_V
%
% プロット（3つ）:
%   1) FRFR vs time (target line)
%   2) Error vs time (0 line)
%   3) ao1 voltage vs time (applied & commanded)
%====================================================================

    if nargin < 1
        t_total = 180; % [s]
    end

    %% --- DAQ / Scope init (same as your existing style) -------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev)); %#ok<NASGU>

    %% --- Parameters --------------------------------------------------
    Ts       = 0.3;      % [s]
    FRFR_ref = 25;       % [ns] target

    ao0_const = 1.54;    % [V]
    u0        = 1.54;    % [V] baseline (command center)
    v_min     = 0.0;
    v_max     = 5.0;

    % ---- 1st-order FB gain (start conservative; tune later) ----------
    % u_cmd = u0 - K * e
    K = 0.002;           % [V/ns] (same scale as before, but now NOT integrated)

    % ---- Safety: rate limit (recommended) ----------------------------
    du_max = 0.02;       % [V] max |Δu| per step

    % ---- Unwrap (your logic; treated as correct) ---------------------
    JUMP_DETECT_NS = 50; % [ns]
    OFFSET_STEP_NS = 100;% [ns]

    %% --- Unwrap state ------------------------------------------------
    prev_raw_frfr = NaN;
    frfr_offset   = 0;

    %% --- Logs --------------------------------------------------------
    time_log = [];
    frfr_log = [];
    err_log  = [];
    ao1_log  = [];
    ucmd_log = [];

    %% --- Initial output ---------------------------------------------
    u_applied = clamp(u0, v_min, v_max);
    outputSingleScan(s, [ao0_const, u_applied]);

    %% --- Main loop ---------------------------------------------------
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > t_total
            break;
        end

        % ---- FRFR read ----
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        raw_frfr = frfr_sec * 1e9; % [ns]

        % ---- Unwrap (your logic) ----
        if ~isnan(prev_raw_frfr)
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
            end
        end
        frfr_corr = raw_frfr + frfr_offset;
        prev_raw_frfr = raw_frfr;

        % ---- Error (state) ----
        e = frfr_corr - FRFR_ref;

        % ---- 1st-order FB: absolute command (NO integration) ----
        u_cmd = u0 - K * e;
        u_cmd = clamp(u_cmd, v_min, v_max);

        % ---- Rate limit on applied voltage (avoid harsh jumps) ----
        u_next = clamp(u_cmd, u_applied - du_max, u_applied + du_max);
        u_next = clamp(u_next, v_min, v_max);

        % ---- Output ----
        try
            outputSingleScan(s, [ao0_const, u_next]);
        catch ME
            warning("DAQ output error: %s", ME.message);
            break;
        end
        u_applied = u_next;

        % ---- Log ----
        time_log(end+1) = t;           %#ok<AGROW>
        frfr_log(end+1) = frfr_corr;   %#ok<AGROW>
        err_log(end+1)  = e;           %#ok<AGROW>
        ao1_log(end+1)  = u_applied;   %#ok<AGROW>
        ucmd_log(end+1) = u_cmd;       %#ok<AGROW>

        fprintf("t=%.1f s | FRFR=%.2f ns | e=%.2f ns | ao1=%.4f V | u_cmd=%.4f V\n", ...
                t, frfr_corr, e, u_applied, u_cmd);

        pause(Ts);
    end

    %% --- Save CSV ----------------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_statefb_1st_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), frfr_log(:), err_log(:), ao1_log(:), ucmd_log(:), ...
        'VariableNames', {'time_s','frfr_ns','err_ns','ao1_V','u_cmd_V'} );

    writetable(log_tbl, log_name);
    fprintf("Saved log: %s\n", log_name);

    %% --- Plots (3) ---------------------------------------------------
    figure('Name','FRFR vs time','NumberTitle','off');
    plot(time_log, frfr_log, 'LineWidth', 2); grid on; hold on;
    yline(FRFR_ref, 'r--', 'Target 25 ns');
    xlabel('Time [s]'); ylabel('FRFR [ns]'); title('FRFR');

    figure('Name','Error vs time','NumberTitle','off');
    plot(time_log, err_log, 'LineWidth', 2); grid on; hold on;
    yline(0, 'r--', 'Target error=0');
    xlabel('Time [s]'); ylabel('Error [ns]'); title('Error');

    figure('Name','Control Voltage','NumberTitle','off');
    plot(time_log, ao1_log, 'LineWidth', 2); hold on;
    plot(time_log, ucmd_log, '--', 'LineWidth', 1.5);
    grid on;
    xlabel('Time [s]'); ylabel('ao1 [V]');
    legend('Applied','Commanded');
    title('Control Voltage');

    %% --- Return ------------------------------------------------------
    result = struct();
    result.log_csv = log_name;
    result.params = struct( ...
        'Ts', Ts, 't_total', t_total, 'FRFR_ref', FRFR_ref, ...
        'ao0_const', ao0_const, 'u0', u0, 'v_min', v_min, 'v_max', v_max, ...
        'K', K, 'du_max', du_max, ...
        'JUMP_DETECT_NS', JUMP_DETECT_NS, 'OFFSET_STEP_NS', OFFSET_STEP_NS, ...
        'ip', ip );
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end
