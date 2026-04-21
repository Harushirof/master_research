function result = frfr_pll_state_space_fb_single_run(t_total)
%====================================================================
% FRFR absolute target tracking (PLL-like) using 2-state feedback
% Goal: FRFR (absolute) -> 25 ns, not just frequency sync.
%
% States:
%   x1 = phase_error_ns = wrap_to_range(frfr - FRFR_ref, -100, 100)
%   x2 = freq_err_ns_per_s ~= d(frfr_unwrapped)/dt
%
% Control (absolute command, NOT integrating u):
%   u_cmd = u0 - k1*x1 - k2*x2
%   u_applied = rate_limited(u_cmd)
%
% Measurement:
%   SIGLENT SDS2204X: MEAS:ADV:P3:VAL?  (sec) -> ns
%
% Unwrap:
%   Use your exact unwrap logic (JUMP_DETECT_NS=50, OFFSET_STEP_NS=100) as-is.
%
% Outputs:
%   CSV log + 3 plots
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
    Ts = 0.3;                   % [s] FB period
    FRFR_ref = 25;              % [ns] absolute target
    wrap_lo = -100;             % [ns]
    wrap_hi =  100;             % [ns]

    ao0_const = 1.54;           % [V]
    u0        = 1.54;           % [V] nominal baseline
    v_min     = 0.0;            % [V]
    v_max     = 5.0;            % [V]

    % --- Gains (start conservative; tune) -----------------------------
    % u_cmd = u0 - k1*phase_error - k2*freq_err
    k1 = 0.0010;                % [V/ns]
    k2 = 0.0002;                % [V/(ns/s)]

    % --- Rate limit on applied voltage --------------------------------
    du_max = 0.02;              % [V] per step

    % --- Unwrap (YOUR logic; treated as correct) ----------------------
    JUMP_DETECT_NS = 50;        % [ns]
    OFFSET_STEP_NS = 100;       % [ns]

    %% --- Unwrap state ------------------------------------------------
    prev_raw_frfr = NaN;
    frfr_offset   = 0;
    prev_frfr_unwrapped = NaN;

    %% --- Logs --------------------------------------------------------
    time_log  = [];
    frfr_u_log = [];    % unwrapped
    frfr_w_log = [];    % wrapped to [-100,100]
    perr_log  = [];     % phase error to target (wrapped)
    ferr_log  = [];     % freq_err (ns/s)
    ao1_log   = [];     % applied
    ucmd_log  = [];     % commanded

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
        raw_frfr = frfr_sec * 1e9; % [ns] (wrapped as returned)

        % ---- Unwrap (your logic) ----
        if ~isnan(prev_raw_frfr)
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
            end
        end
        frfr_unwrapped = raw_frfr + frfr_offset;
        prev_raw_frfr  = raw_frfr;

        % ---- Wrapped FRFR (for absolute target) ----
        frfr_wrapped = wrap_to_range(frfr_unwrapped, wrap_lo, wrap_hi);

        % ---- Phase error (wrapped shortest error to target) ----
        phase_err = wrap_to_range(frfr_wrapped - FRFR_ref, wrap_lo, wrap_hi);

        % ---- Freq error estimate (ns/s) using unwrapped derivative ----
        if isnan(prev_frfr_unwrapped)
            freq_err = 0;
        else
            freq_err = (frfr_unwrapped - prev_frfr_unwrapped) / Ts;
        end
        prev_frfr_unwrapped = frfr_unwrapped;

        % ---- 2-state feedback (absolute command; no u integration) ----
        u_cmd = u0 - k1 * phase_err - k2 * freq_err;
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
        time_log(end+1)   = t;              %#ok<AGROW>
        frfr_u_log(end+1) = frfr_unwrapped; %#ok<AGROW>
        frfr_w_log(end+1) = frfr_wrapped;   %#ok<AGROW>
        perr_log(end+1)   = phase_err;      %#ok<AGROW>
        ferr_log(end+1)   = freq_err;       %#ok<AGROW>
        ao1_log(end+1)    = u_applied;      %#ok<AGROW>
        ucmd_log(end+1)   = u_cmd;          %#ok<AGROW>

        fprintf("t=%.1f | FRFR(w)=%.2f ns | e=%.2f ns | df=%.3f ns/s | ao1=%.4f V | u_cmd=%.4f V\n", ...
            t, frfr_wrapped, phase_err, freq_err, u_applied, u_cmd);

        pause(Ts);
    end

    %% --- Save CSV ----------------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_pll_statefb_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), frfr_u_log(:), frfr_w_log(:), perr_log(:), ferr_log(:), ao1_log(:), ucmd_log(:), ...
        'VariableNames', {'time_s','frfr_unwrapped_ns','frfr_wrapped_ns','phase_err_ns','freq_err_ns_per_s','ao1_V','u_cmd_V'} );

    writetable(log_tbl, log_name);
    fprintf("Saved log: %s\n", log_name);

    %% --- Plots (3) ---------------------------------------------------
    figure('Name','FRFR (wrapped) vs time','NumberTitle','off');
    plot(time_log, frfr_w_log, 'LineWidth', 2); grid on; hold on;
    yline(FRFR_ref, 'r--', 'Target 25 ns');
    xlabel('Time [s]'); ylabel('FRFR (wrapped) [ns]');
    title('FRFR (Absolute Target Tracking)');

    figure('Name','Freq error vs time','NumberTitle','off');
    plot(time_log, ferr_log, 'LineWidth', 2); grid on; hold on;
    yline(0, 'r--', 'Target df=0');
    xlabel('Time [s]'); ylabel('freq\_err [ns/s]');
    title('Estimated Frequency Error');

    figure('Name','ao1 voltage vs time','NumberTitle','off');
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
        'wrap_lo', wrap_lo, 'wrap_hi', wrap_hi, ...
        'ao0_const', ao0_const, 'u0', u0, 'v_min', v_min, 'v_max', v_max, ...
        'k1', k1, 'k2', k2, 'du_max', du_max, ...
        'JUMP_DETECT_NS', JUMP_DETECT_NS, 'OFFSET_STEP_NS', OFFSET_STEP_NS, ...
        'ip', ip );
end

%% --- Helpers ---------------------------------------------------------
function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function y = wrap_to_range(x, lo, hi)
% wrap x into [lo, hi) assuming period = hi-lo
    P = hi - lo;
    y = mod(x - lo, P) + lo;
    % optional: represent hi as hi (not hi-ε)
    if y == hi
        y = lo;
    end
end
