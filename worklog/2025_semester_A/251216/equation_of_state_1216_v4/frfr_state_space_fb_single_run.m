function result = frfr_df0_statefb_single_run(t_total)
%====================================================================
% 目的：周波数差分（≒ d(FRFR_unwrapped)/dt）を 0 に収束させる（Δf→0）
%
% 重要：
% - FRFR の「値」をターゲットにしない（25ns等は使わない）
% - 制御誤差は freq_err = ΔFRFR_unwrapped / Ts [ns/s]
% - u_cmd = u0 - K_df * freq_err   （uを積分更新しない）
%
% アンラップ：ユーザー提示ロジックをそのまま使用（正）
%   JUMP_DETECT_NS = 50
%   OFFSET_STEP_NS = 100
%
% 出力：
%   result.log_csv : 保存ログCSV名
%   ログCSV列：
%     time_s, raw_frfr_ns, frfr_unwrapped_ns, freq_err_ns_per_s,
%     ao1_V, u_cmd_V, unwrap_offset_ns
%
% プロット（3つ）：
%   1) FRFR_unwrapped vs time
%   2) Δf proxy vs time（freq_err_ns_per_s vs time）  ← 要望のΔf-t
%   3) ao1 voltage vs time（applied & commanded）
%====================================================================

    if nargin < 1
        t_total = 180; % [s]
    end

    %% --- DAQ / Scope init -------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev)); %#ok<NASGU>

    %% --- Parameters --------------------------------------------------
    Ts = 0.3;            % [s] FB period (you said 0.3s)

    ao0_const = 1.54;    % [V]
    u0        = 1.54;    % [V] baseline center
    v_min     = 0.0;
    v_max     = 5.0;

    % ---- Control gain for Δf-proxy (freq_err) ------------------------
    % u_cmd = u0 - K_df * freq_err_ns_per_s
    % 単位：K_df [V / (ns/s)]
    K_df = 0.0010;       % 初期値（安全寄り）。必要なら後で調整。

    % ---- Safety: rate limit -----------------------------------------
    du_max = 0.02;       % [V] max |Δu| per step

    % ---- Unwrap (YOUR EXACT LOGIC; DO NOT CHANGE) --------------------
    JUMP_DETECT_NS = 50; % [ns]
    OFFSET_STEP_NS = 100;% [ns]

    %% --- Unwrap / derivative state ----------------------------------
    prev_raw_frfr = NaN;
    frfr_offset   = 0;

    prev_frfr_u   = NaN; % previous unwrapped FRFR

    %% --- Logs --------------------------------------------------------
    time_log   = [];
    raw_log    = [];
    frfr_u_log = [];
    df_log     = [];     % freq_err_ns_per_s
    ao1_log    = [];
    ucmd_log   = [];
    off_log    = [];

    %% --- Initial output ---------------------------------------------
    u_applied = clamp(u0, v_min, v_max);
    outputSingleScan(s, [ao0_const, u_applied]);

    fprintf("START Δf→0 control | Ts=%.3f s | K_df=%.6f V/(ns/s) | unwrap jump=%g step=%g\n", ...
        Ts, K_df, JUMP_DETECT_NS, OFFSET_STEP_NS);

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

        % ---- Unwrap (YOUR logic) ----
        if ~isnan(prev_raw_frfr)
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
            end
        end
        frfr_u = raw_frfr + frfr_offset;
        prev_raw_frfr = raw_frfr;

        % ---- Δf proxy (freq_err) ----
        if isnan(prev_frfr_u)
            freq_err = 0; % 初回は0扱い（制御を暴れさせない）
        else
            freq_err = (frfr_u - prev_frfr_u) / Ts; % [ns/s]
        end
        prev_frfr_u = frfr_u;

        % ---- Control: target freq_err -> 0 (absolute command, NO integration) ----
        u_cmd = u0 - K_df * freq_err;
        u_cmd = clamp(u_cmd, v_min, v_max);

        % ---- Rate limit applied voltage ----
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
        time_log(end+1)   = t;        %#ok<AGROW>
        raw_log(end+1)    = raw_frfr; %#ok<AGROW>
        frfr_u_log(end+1) = frfr_u;   %#ok<AGROW>
        df_log(end+1)     = freq_err; %#ok<AGROW>
        ao1_log(end+1)    = u_applied; %#ok<AGROW>
        ucmd_log(end+1)   = u_cmd;    %#ok<AGROW>
        off_log(end+1)    = frfr_offset; %#ok<AGROW>

        fprintf("t=%.1f | FRFR_u=%.2f ns | df=%.3f ns/s | ao1=%.4f V | u_cmd=%.4f V | off=%.1f\n", ...
            t, frfr_u, freq_err, u_applied, u_cmd, frfr_offset);

        pause(Ts);
    end

    %% --- Save CSV ----------------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_df0_statefb_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), raw_log(:), off_log(:), frfr_u_log(:), df_log(:), ao1_log(:), ucmd_log(:), ...
        'VariableNames', {'time_s','raw_frfr_ns','unwrap_offset_ns','frfr_unwrapped_ns', ...
                          'freq_err_ns_per_s','ao1_V','u_cmd_V'} );

    writetable(log_tbl, log_name);
    fprintf("Saved log: %s\n", log_name);

    %% --- Plots -------------------------------------------------------
    figure('Name','FRFR (UNWRAPPED)','NumberTitle','off');
    plot(time_log, frfr_u_log, 'LineWidth', 2); grid on;
    xlabel('Time [s]'); ylabel('FRFR unwrapped [ns]');
    title('FRFR (UNWRAPPED)');

    figure('Name','Δf proxy (freq_err) vs time','NumberTitle','off');
    plot(time_log, df_log, 'LineWidth', 2); grid on; hold on;
    yline(0, 'r--', 'Target 0');
    xlabel('Time [s]'); ylabel('Δf proxy = d(FRFR)/dt [ns/s]');
    title('Δf - t (proxy: freq\_err\_ns\_per\_s)');

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
        'Ts', Ts, 't_total', t_total, ...
        'ao0_const', ao0_const, 'u0', u0, 'v_min', v_min, 'v_max', v_max, ...
        'K_df', K_df, 'du_max', du_max, ...
        'JUMP_DETECT_NS', JUMP_DETECT_NS, 'OFFSET_STEP_NS', OFFSET_STEP_NS, ...
        'ip', ip );
end

%% ===== Helpers ======================================================
function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev)
% cleanupDAQ  DAQとオシロを安全にクローズし、電圧を0Vに戻す
    try
        if ~isempty(s.Channels)
            n = numel(s.Channels);
            outputSingleScan(s, zeros(1,n));
        end
    catch
    end
    try, stop(s);    catch, end
    try, release(s); catch, end
    try, clear dev;  catch, end
    fprintf("cleanupDAQ: all outputs set to 0V and session released.\n");
end
