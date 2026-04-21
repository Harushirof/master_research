function result = frfr_verify_B_wrapped_fb_test(t_total, FRFR_ref)
%====================================================================
% Verify-B: Prove you are running the WRAPPED-error controller (single target e_phi->0).
% - Unique function name to avoid calling an old file.
% - Logs which(mfilename) to CSV + prints it.
% - Asserts e_phi and dy are always within [-T/2, T/2).
%====================================================================

    if nargin < 1 || isempty(t_total),  t_total = 90; end
    if nargin < 2 || isempty(FRFR_ref), FRFR_ref = 25; end

    %% --- Signature (human check) ---
    SIGNATURE = "WRAPPED_FB_TEST_V20260121";
    fprintf("=== %s ===\n", SIGNATURE);
    fprintf("Function path: %s\n", which(mfilename));

    %% --- Params ---
    ip  = "192.168.1.61";

    Ts          = 0.3;    % [s]
    T_period_ns = 100;    % [ns]
    FRFR_is_seconds = true;

    ao0_const = 1.54;     % keep fixed here
    u0        = 1.54;     % baseline ao1
    v_min     = 0.0; v_max = 5.0;

    k1 = 0.002;           % [V/ns]
    k2 = 0.005;           % [V/(ns/s)]
    alpha = 0.2;

    du_max = 0.02;        % [V/step]

    SAFE_AO0_V = 0.0;
    SAFE_AO1_V = 0.0;

    %% --- Init DAQ / Scope ---
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev, SAFE_AO0_V, SAFE_AO1_V)); %#ok<NASGU>

    %% --- State / logs ---
    prev_frfr_ns = NaN;
    frfrdot_hat  = 0;
    u_applied    = clamp(u0, v_min, v_max);

    outputSingleScan(s, [ao0_const, u_applied]);

    time_log        = [];
    frfr_w_log      = [];
    ephi_log        = [];
    dy_log          = [];
    dot_raw_log     = [];
    dot_hat_log     = [];
    ao1_log         = [];
    ucmd_log        = [];
    which_log       = strings(0,1);

    t0 = tic;

    while true
        t = toc(t0);
        if t > t_total
            break;
        end

        % Read FRFR
        writeline(dev, "MEAS:ADV:P3:VAL?");
        val = str2double(readline(dev));
        if isnan(val)
            warning("FRFR NaN. Abort.");
            break;
        end
        if FRFR_is_seconds
            frfr_ns_meas = val * 1e9;
        else
            frfr_ns_meas = val;
        end

        % Normalize to [-T/2,T/2)
        frfr_w = wrapToHalfPeriod(frfr_ns_meas, T_period_ns);

        % Wrapped phase error (single target e_phi -> 0)
        e_phi = wrapToHalfPeriod(frfr_w - FRFR_ref, T_period_ns);

        % Wrapped delta for derivative
        if isnan(prev_frfr_ns)
            dy = 0;
            dt = Ts;
        else
            dy = wrapToHalfPeriod(frfr_w - prev_frfr_ns, T_period_ns);
            dt = Ts;
        end
        prev_frfr_ns = frfr_w;

        % Assertions (detect wrong logic / wrong scaling early)
        if abs(e_phi) > (T_period_ns/2 + 1e-6)
            error("e_phi out of range: %.3f ns (should be within ±%.1f)", e_phi, T_period_ns/2);
        end
        if abs(dy) > (T_period_ns/2 + 1e-6)
            error("dy out of range: %.3f ns (should be within ±%.1f)", dy, T_period_ns/2);
        end

        frfrdot_raw = dy / dt; % [ns/s]
        frfrdot_hat = (1-alpha)*frfrdot_hat + alpha*frfrdot_raw;

        % Control
        u_cmd = u0 - k1*e_phi - k2*frfrdot_hat;
        u_cmd = clamp(u_cmd, v_min, v_max);

        u_next = clamp(u_cmd, u_applied - du_max, u_applied + du_max);
        u_next = clamp(u_next, v_min, v_max);

        outputSingleScan(s, [ao0_const, u_next]);
        u_applied = u_next;

        % Log
        time_log(end+1,1)    = t;           %#ok<AGROW>
        frfr_w_log(end+1,1)  = frfr_w;      %#ok<AGROW>
        ephi_log(end+1,1)    = e_phi;       %#ok<AGROW>
        dy_log(end+1,1)      = dy;          %#ok<AGROW>
        dot_raw_log(end+1,1) = frfrdot_raw; %#ok<AGROW>
        dot_hat_log(end+1,1) = frfrdot_hat; %#ok<AGROW>
        ao1_log(end+1,1)     = u_applied;   %#ok<AGROW>
        ucmd_log(end+1,1)    = u_cmd;       %#ok<AGROW>
        which_log(end+1,1)   = string(which(mfilename)); %#ok<AGROW>

        fprintf("t=%.1f | FRFR(w)=%.2f ns | e_phi=%.2f ns | dy=%.2f ns | dot_hat=%.3f ns/s | ao1=%.4f V | u_cmd=%.4f V\n", ...
            t, frfr_w, e_phi, dy, frfrdot_hat, u_applied, u_cmd);

        pause(Ts);
    end

    %% --- Save CSV ---
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_verify_B_wrapped_fb_test_%s.csv', timestamp);

    tbl = table( ...
        time_log, frfr_w_log, ephi_log, dy_log, dot_raw_log, dot_hat_log, ao1_log, ucmd_log, which_log, ...
        'VariableNames', {'time_s','frfr_wrapped_ns','e_phi_ns','dy_wrapped_ns','frfrdot_raw_nsps','frfrdot_hat_nsps','ao1_V','u_cmd_V','which_path'} );

    writetable(tbl, log_name);
    fprintf("Saved: %s\n", log_name);

    % Plots
    figure('Name','Verify-B: FRFR(wrapped) & target','NumberTitle','off');
    plot(time_log, frfr_w_log, 'LineWidth', 2); grid on; hold on;
    yline(wrapToHalfPeriod(FRFR_ref, T_period_ns),'r--','Target');
    xlabel('Time [s]'); ylabel('FRFR wrapped [ns]');

    figure('Name','Verify-B: e\_phi (wrapped error)','NumberTitle','off');
    plot(time_log, ephi_log, 'LineWidth', 2); grid on; hold on;
    yline(0,'r--','Target 0');
    xlabel('Time [s]'); ylabel('e\_phi [ns]');

    figure('Name','Verify-B: FRFRdot\_hat','NumberTitle','off');
    plot(time_log, dot_hat_log, 'LineWidth', 2); grid on; hold on;
    yline(0,'r--','Target 0 ns/s');
    xlabel('Time [s]'); ylabel('FRFRdot hat [ns/s]');

    figure('Name','Verify-B: ao1 voltage','NumberTitle','off');
    plot(time_log, ao1_log, 'LineWidth', 2); hold on;
    plot(time_log, ucmd_log, '--', 'LineWidth', 1.5);
    grid on; xlabel('Time [s]'); ylabel('ao1 [V]');
    legend('Applied','Commanded');

    % Return
    result = struct();
    result.signature = SIGNATURE;
    result.csv = log_name;
    result.which_path = which(mfilename);
    result.params = struct('Ts',Ts,'T_period_ns',T_period_ns,'FRFR_ref',FRFR_ref,'ao0_const',ao0_const,'u0',u0,'k1',k1,'k2',k2,'alpha',alpha,'du_max',du_max,'ip',ip);
end

% ---- helpers ----
function z = wrapToHalfPeriod(x, T)
    z = mod(x + T/2, T) - T/2;
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0, safe_ao1)
    try
        outputSingleScan(s, [safe_ao0, safe_ao1]);
    catch
    end
    try
        release(s);
    catch
    end
    try
        clear dev;
    catch
    end
end
