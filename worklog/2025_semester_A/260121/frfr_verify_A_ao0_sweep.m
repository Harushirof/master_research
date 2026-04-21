function result = frfr_verify_A_ao0_sweep()
%====================================================================
% Verify-A: ao0_const sweep to find operating point where FRFRdot ~= 0
% Assumptions:
% - FRFR measurement wraps with period T_period_ns (default 100ns)
% - We do NOT cumulative-unwrap; we only wrap the delta for derivative.
%
% Outputs:
% - CSV: frfr_verify_A_ao0_sweep_yyyymmdd_HHMMSS.csv
% - Console: estimated ao0* where FRFRdot=0 (linear fit)
%====================================================================

    %% ---------- User-set parameters ----------
    ip  = "192.168.1.61";

    Ts          = 0.3;    % sampling interval [s]
    T_period_ns = 100;    % wrap period [ns]
    FRFR_is_seconds = true; % if scope returns seconds, set true

    ao1_fixed = 1.54;     % keep ao1 fixed while sweeping ao0
    v_min = 0.0; v_max = 5.0;

    % Sweep settings
    ao0_list = [0.0 0.5 1.0 1.2 1.4 1.54 1.7 2.0 2.5 3.0 3.5 4.0 4.5 5.0];

    settle_s = 2.0;       % wait after setting ao0 [s]
    window_s = 12.0;      % measurement window per point [s] (>= ~30 samples recommended)
    alpha    = 0.2;       % EMA for frfrdot_hat (optional; can keep)

    SAFE_AO0_V = 0.0;
    SAFE_AO1_V = 0.0;

    %% ---------- Init DAQ / Scope ----------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev, SAFE_AO0_V, SAFE_AO1_V)); %#ok<NASGU>

    %% ---------- Sweep loop ----------
    nP = numel(ao0_list);
    ao0_V = zeros(nP,1);
    ao1_V = zeros(nP,1);
    dot_mean = zeros(nP,1);
    dot_std  = zeros(nP,1);
    dot_med  = zeros(nP,1);
    n_samp   = zeros(nP,1);

    fprintf("=== Verify-A (ao0 sweep) ===\n");
    fprintf("Function path: %s\n", which(mfilename));
    fprintf("ao1 fixed = %.4f V\n", ao1_fixed);
    fprintf("Ts=%.3f s, T_period=%.1f ns, window=%.1f s\n", Ts, T_period_ns, window_s);

    for i = 1:nP
        ao0 = clamp(ao0_list(i), v_min, v_max);
        ao1 = clamp(ao1_fixed,  v_min, v_max);

        % Apply voltages
        outputSingleScan(s, [ao0, ao1]);
        pause(settle_s);

        % Measure FRFRdot over window
        [dot_series, dt_series] = measure_frfrdot_series(dev, Ts, window_s, T_period_ns, FRFR_is_seconds);

        % Optional EMA smoothing (mostly for stability of summary)
        dot_hat = ema(dot_series, alpha);

        ao0_V(i)    = ao0;
        ao1_V(i)    = ao1;
        dot_mean(i) = mean(dot_hat);
        dot_std(i)  = std(dot_hat);
        dot_med(i)  = median(dot_hat);
        n_samp(i)   = numel(dot_hat);

        fprintf("[%-2d/%-2d] ao0=%.3f V | FRFRdot_hat mean=%.4f ns/s (med=%.4f, std=%.4f) | N=%d | dt_mean=%.3f s\n", ...
            i, nP, ao0, dot_mean(i), dot_med(i), dot_std(i), n_samp(i), mean(dt_series));
    end

    %% ---------- Linear fit to estimate ao0* where dot=0 ----------
    % Use median-based robust subset: drop points with extremely large std if needed
    x = ao0_V;
    y = dot_mean;

    % Fit y = a*x + b
    p = polyfit(x, y, 1);
    a = p(1); b = p(2);

    if abs(a) < 1e-9
        ao0_star = NaN;
    else
        ao0_star = -b/a;
    end

    fprintf("\n=== Fit result: FRFRdot_mean ≈ a*ao0 + b ===\n");
    fprintf("a = %.6f [ns/s/V], b = %.6f [ns/s]\n", a, b);
    fprintf("Estimated ao0* where FRFRdot=0: %.4f V\n", ao0_star);
    fprintf("Within [0,5]? %s\n", string(~isnan(ao0_star) && ao0_star>=v_min && ao0_star<=v_max));

    %% ---------- Save CSV ----------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_verify_A_ao0_sweep_%s.csv', timestamp);

    tbl = table(ao0_V, ao1_V, dot_mean, dot_med, dot_std, n_samp, ...
        'VariableNames', {'ao0_V','ao1_V','frfrdot_hat_mean_nsps','frfrdot_hat_median_nsps','frfrdot_hat_std_nsps','N'});

    writetable(tbl, log_name);
    fprintf("Saved: %s\n", log_name);

    %% ---------- Plot ----------
    figure('Name','Verify-A: FRFRdot vs ao0','NumberTitle','off');
    plot(ao0_V, dot_mean, 'o-', 'LineWidth', 1.5); grid on; hold on;
    yline(0,'r--','Target 0');
    xlabel('ao0 [V]'); ylabel('FRFRdot_hat mean [ns/s]');
    title(sprintf('FRFRdot vs ao0 (ao1 fixed=%.3fV), ao0*≈%.3fV', ao1_fixed, ao0_star));

    %% ---------- Return ----------
    result = struct();
    result.csv = log_name;
    result.fit = struct('a',a,'b',b,'ao0_star',ao0_star);
    result.params = struct('Ts',Ts,'T_period_ns',T_period_ns,'window_s',window_s,'settle_s',settle_s,'ao1_fixed',ao1_fixed,'ao0_list',ao0_list,'ip',ip);
end

% ---------------- helpers (same file) ----------------
function [dot_series, dt_series] = measure_frfrdot_series(dev, Ts, window_s, T_period_ns, FRFR_is_seconds)
    t0 = tic;

    prev_frfr = NaN;
    prev_t    = NaN;

    dot_series = [];
    dt_series  = [];

    while toc(t0) < window_s
        % Read FRFR
        writeline(dev, "MEAS:ADV:P3:VAL?");
        val = str2double(readline(dev));
        if isnan(val)
            continue;
        end
        if FRFR_is_seconds
            frfr_ns_meas = val * 1e9;
        else
            frfr_ns_meas = val;
        end

        frfr_ns = wrapToHalfPeriod(frfr_ns_meas, T_period_ns);
        t_now = toc(t0);

        if ~isnan(prev_frfr)
            dt = t_now - prev_t;
            dy = wrapToHalfPeriod(frfr_ns - prev_frfr, T_period_ns);
            dot = dy / dt;

            dot_series(end+1,1) = dot; %#ok<AGROW>
            dt_series(end+1,1)  = dt;  %#ok<AGROW>
        end

        prev_frfr = frfr_ns;
        prev_t    = t_now;

        pause(Ts);
    end
end

function xhat = ema(x, alpha)
    if isempty(x)
        xhat = x;
        return;
    end
    xhat = zeros(size(x));
    xhat(1) = x(1);
    for k = 2:numel(x)
        xhat(k) = (1-alpha)*xhat(k-1) + alpha*x(k);
    end
end

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
