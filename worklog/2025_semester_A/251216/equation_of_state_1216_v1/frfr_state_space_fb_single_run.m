function result = frfr_state_space_fb_single_run(t_total)
%====================================================================
% 状態方程式ベース（最小1状態）のFRFR制御（ao1電圧を更新）
% - FRFR target: 25 ns
% - Ts = 0.3 s
% - アンラップ: ユーザー提示ロジック（JUMP_DETECT_NS=50, OFFSET_STEP_NS=100）を正とする
%
% 出力:
%   result.log_csv : 保存ログCSV名
%   result.params  : 使用パラメータ構造体
%
% ログCSV列:
%   time_s, frfr_ns, err_ns, ao1_V, dv_fb_V
%
% プロット（3つ）:
%   1) FRFR vs time (target line)
%   2) Error vs time (0 line)
%   3) ao1 voltage vs time
%====================================================================

    if nargin < 1
        t_total = 180; % [s]
    end

    %% --- Fixed I/O (use your existing connection style) -------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev)); %#ok<NASGU>

    %% --- Parameters --------------------------------------------------
    Ts = 0.3;              % [s] FB update period
    FRFR_ref = 25;         % [ns] target

    ao0_const = 1.54;      % [V] fixed bias
    v_fb      = 1.54;      % [V] control baseline (ao1)
    v_min     = 0.0;
    v_max     = 5.0;

    % --- State-feedback gain (tune later) ---
    % u_k = u_{k-1} - K_e * e_k
    % e_k = frfr_corr - FRFR_ref
    K_e = 0.002;           % [V/ns] start small

    % --- Voltage step constraint (optional but safe) ---
    du_max = 0.02;         % [V] max |Δu| per step
    min_step = 0.000;      % [V] (set >0 if you want to avoid stalling)

    % --- Unwrap (AS-IS from your code; treated as correct) ---
    JUMP_DETECT_NS = 50;   % [ns]
    OFFSET_STEP_NS = 100;  % [ns]

    %% --- State variables (unwrap) -----------------------------------
    prev_raw_frfr = NaN;
    frfr_offset   = 0;

    %% --- Logging arrays ---------------------------------------------
    time_log = [];
    frfr_log = [];
    err_log  = [];
    ao1_log  = [];
    dv_log   = [];

    %% --- Initial output ---------------------------------------------
    outputSingleScan(s, [ao0_const, v_fb]);

    %% --- Main loop ---------------------------------------------------
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > t_total
            break;
        end

        % ---- FRFR measurement ----
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        raw_frfr = frfr_sec * 1e9; % [ns]

        % ---- Unwrap (user's logic) ----
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

        % ---- State (error) ----
        e = frfr_corr - FRFR_ref;

        % ---- State feedback update (discrete) ----
        dv_fb = -K_e * e;
        if min_step > 0 && abs(dv_fb) < min_step && dv_fb ~= 0
            dv_fb = min_step * sign(dv_fb);
        end

        % rate limit
        dv_fb = min(max(dv_fb, -du_max), du_max);

        v_fb = v_fb + dv_fb;
        v_fb = min(max(v_fb, v_min), v_max);

        % ---- Output ----
        try
            outputSingleScan(s, [ao0_const, v_fb]);
        catch ME
            warning("DAQ output error: %s", ME.message);
            break;
        end

        % ---- Log ----
        time_log(end+1) = t;            %#ok<AGROW>
        frfr_log(end+1) = frfr_corr;    %#ok<AGROW>
        err_log(end+1)  = e;            %#ok<AGROW>
        ao1_log(end+1)  = v_fb;         %#ok<AGROW>
        dv_log(end+1)   = dv_fb;        %#ok<AGROW>

        fprintf("t=%.1f s | FRFR=%.2f ns | e=%.2f ns | ao1=%.4f V | dv=%.4f V\n", ...
                t, frfr_corr, e, v_fb, dv_fb);

        pause(Ts);
    end

    %% --- Save CSV ----------------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_statefb_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), frfr_log(:), err_log(:), ao1_log(:), dv_log(:), ...
        'VariableNames', {'time_s','frfr_ns','err_ns','ao1_V','dv_fb_V'} );

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

    figure('Name','ao1 voltage vs time','NumberTitle','off');
    plot(time_log, ao1_log, 'LineWidth', 2); grid on;
    xlabel('Time [s]'); ylabel('ao1 [V]'); title('Control Voltage');

    %% --- Return ------------------------------------------------------
    result = struct();
    result.log_csv = log_name;
    result.params = struct( ...
        'Ts', Ts, 't_total', t_total, 'FRFR_ref', FRFR_ref, ...
        'ao0_const', ao0_const, 'v_fb_init', 1.54, 'v_min', v_min, 'v_max', v_max, ...
        'K_e', K_e, 'du_max', du_max, 'min_step', min_step, ...
        'JUMP_DETECT_NS', JUMP_DETECT_NS, 'OFFSET_STEP_NS', OFFSET_STEP_NS, ...
        'ip', ip );
end
