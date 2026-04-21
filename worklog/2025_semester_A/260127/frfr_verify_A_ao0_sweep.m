function result = frfr_verify_A_ao0_sweep()
%====================================================================
% Verify-A (WRAPPED): Sweep ao0 to find operating point where FRFRdot ~= 0
%
% What we want:
%   Does there exist ao0 within [0,5] V such that FRFRdot ~= 0 (ideally 0)?
%
% Critical fix:
%   FRFR is wrapped (e.g., [-50, +50) ns) and can jump near boundaries.
%   Therefore FRFRdot must be estimated from WRAPPED DELTA:
%       dy_wrapped = wrapToHalfPeriod(frfr(k) - frfr(k-1), T_period_ns)
%       frfrdot = dy_wrapped / dt
%   where dt is measured (tic/toc), not assumed Ts.
%
% Outputs:
%   - Summary CSV: frfr_verify_A_ao0_sweep_summary_yyyymmdd_HHMMSS.csv
%   - Detail  CSV: frfr_verify_A_ao0_sweep_detail_yyyymmdd_HHMMSS.csv
%
% Notes:
%   - This function is self-contained; no cleanupDAQ.m required.
%====================================================================

    %% ---------- User-set parameters ----------
    ip  = "192.168.1.61";

    % Sampling
    Ts_target   = 0.3;      % [s] target pause; real dt is measured
    window_s    = 12.0;     % [s] measurement window per ao0 point
    settle_s    = 2.0;      % [s] wait after changing ao0

    % Wrap period (e.g., 10 MHz => 100 ns)
    T_period_ns = 100.0;    % [ns]

    % Instrument unit
    % If "MEAS:ADV:P3:VAL?" returns seconds -> true (convert to ns by *1e9)
    FRFR_is_seconds = true;

    % Voltage bounds
    v_min = 0.0; v_max = 5.0;

    % Fix ao1, sweep ao0
    ao1_fixed = 1.54;       % [V]
    ao0_list  = [0.0 0.5 1.0 1.2 1.4 1.54 1.7 2.0 2.5 3.0 3.5 4.0 4.5 5.0];

    % Optional smoothing for dot series (EMA)
    use_ema = true;
    alpha   = 0.2;          % EMA factor

    % Safety outputs at cleanup
    SAFE_AO0_V = 0.0;
    SAFE_AO1_V = 0.0;

    %% ---------- Init DAQ / Scope ----------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev, SAFE_AO0_V, SAFE_AO1_V)); %#ok<NASGU>

    fprintf("=== Verify-A (WRAPPED delta) ao0 sweep ===\n");
    fprintf("Function path: %s\n", which(mfilename));
    fprintf("ao1_fixed=%.4f V | Ts_target=%.3f s | window=%.1f s | settle=%.1f s | T_period=%.1f ns\n", ...
        ao1_fixed, Ts_target, window_s, settle_s, T_period_ns);

    %% ---------- Preallocate summary ----------
    nP = numel(ao0_list);
    ao0_V      = zeros(nP,1);
    ao1_V      = zeros(nP,1);
    dot_mean   = zeros(nP,1);
    dot_median = zeros(nP,1);
    dot_std    = zeros(nP,1);
    n_samp     = zeros(nP,1);
    dt_mean    = zeros(nP,1);

    %% ---------- Detail logs (grow) ----------
    d_point_idx      = [];
    d_ao0_V          = [];
    d_ao1_V          = [];
    d_t_local_s      = [];
    d_frfr_meas_ns   = [];
    d_frfr_wrapped_ns= [];
    d_dy_wrapped_ns  = [];
    d_dt_s           = [];
    d_frfrdot_nsps   = [];
    d_frfrdot_hat_nsps = [];

    %% ---------- Sweep loop ----------
    for i = 1:nP
        ao0 = clamp(ao0_list(i), v_min, v_max);
        ao1 = clamp(ao1_fixed,  v_min, v_max);

        % Apply and settle
        outputSingleScan(s, [ao0, ao1]);
        pause(settle_s);

        % Measure series (wrapped-delta derivative)
        [frfr_meas_ns, frfr_w_ns, dy_w_ns, dt_s, dot_nsps] = measure_wrapped_dot_series( ...
            dev, Ts_target, window_s, T_period_ns, FRFR_is_seconds);

        % Optional smoothing
        if use_ema
            dot_hat = ema(dot_nsps, alpha);
        else
            dot_hat = dot_nsps;
        end

        % Summary
        ao0_V(i)      = ao0;
        ao1_V(i)      = ao1;
        dot_mean(i)   = mean(dot_hat);
        dot_median(i) = median(dot_hat);
        dot_std(i)    = std(dot_hat);
        n_samp(i)     = numel(dot_hat);
        dt_mean(i)    = mean(dt_s);

        fprintf("[%-2d/%-2d] ao0=%.3f V | FRFRdot_hat mean=%.4f ns/s (med=%.4f, std=%.4f) | N=%d | dt_mean=%.3f s\n", ...
            i, nP, ao0, dot_mean(i), dot_median(i), dot_std(i), n_samp(i), dt_mean(i));

        % Append detail logs
        m = numel(dot_hat);
        d_point_idx       = [d_point_idx;       repmat(i, m, 1)]; %#ok<AGROW>
        d_ao0_V           = [d_ao0_V;           repmat(ao0, m, 1)]; %#ok<AGROW>
        d_ao1_V           = [d_ao1_V;           repmat(ao1, m, 1)]; %#ok<AGROW>
        d_t_local_s       = [d_t_local_s;       (1:m)' * dt_mean(i)]; %#ok<AGROW> % rough local time axis
        d_frfr_meas_ns    = [d_frfr_meas_ns;    frfr_meas_ns(end-m+1:end)]; %#ok<AGROW>
        d_frfr_wrapped_ns = [d_frfr_wrapped_ns; frfr_w_ns(end-m+1:end)]; %#ok<AGROW>
        d_dy_wrapped_ns   = [d_dy_wrapped_ns;   dy_w_ns(end-m+1:end)]; %#ok<AGROW>
        d_dt_s            = [d_dt_s;            dt_s(end-m+1:end)]; %#ok<AGROW>
        d_frfrdot_nsps    = [d_frfrdot_nsps;    dot_nsps(end-m+1:end)]; %#ok<AGROW>
        d_frfrdot_hat_nsps= [d_frfrdot_hat_nsps;dot_hat(:)]; %#ok<AGROW>
    end

    %% ---------- Fit dot_mean vs ao0 to estimate ao0* where dot=0 ----------
    x = ao0_V;
    y = dot_mean;

    p = polyfit(x, y, 1); % y = a*x + b
    a = p(1); b = p(2);

    if abs(a) < 1e-12
        ao0_star = NaN;
    else
        ao0_star = -b / a;
    end

    fprintf("\n=== Linear fit: FRFRdot_mean ≈ a*ao0 + b ===\n");
    fprintf("a = %.6f [ns/s/V], b = %.6f [ns/s]\n", a, b);
    fprintf("Estimated ao0* (dot=0): %.4f V | within [0,5]? %s\n", ...
        ao0_star, string(~isnan(ao0_star) && ao0_star>=v_min && ao0_star<=v_max));

    %% ---------- Save CSVs ----------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    summary_name = sprintf('frfr_verify_A_ao0_sweep_summary_%s.csv', timestamp);
    detail_name  = sprintf('frfr_verify_A_ao0_sweep_detail_%s.csv',  timestamp);

    summary_tbl = table(ao0_V, ao1_V, dot_mean, dot_median, dot_std, n_samp, dt_mean, ...
        'VariableNames', {'ao0_V','ao1_V','frfrdot_hat_mean_nsps','frfrdot_hat_median_nsps','frfrdot_hat_std_nsps','N','dt_mean_s'});

    detail_tbl = table(d_point_idx, d_ao0_V, d_ao1_V, d_frfr_meas_ns, d_frfr_wrapped_ns, d_dy_wrapped_ns, d_dt_s, d_frfrdot_nsps, d_frfrdot_hat_nsps, ...
        'VariableNames', {'point_idx','ao0_V','ao1_V','frfr_meas_ns','frfr_wrapped_ns','dy_wrapped_ns','dt_s','frfrdot_nsps','frfrdot_hat_nsps'});

    writetable(summary_tbl, summary_name);
    writetable(detail_tbl,  detail_name);

    fprintf("Saved summary: %s\n", summary_name);
    fprintf("Saved detail : %s\n", detail_name);

    %% ---------- Plots ----------
    figure('Name','Verify-A: FRFRdot vs ao0 (wrapped-delta)','NumberTitle','off');
    plot(ao0_V, dot_mean, 'o-', 'LineWidth', 1.5); grid on; hold on;
    yline(0,'r--','Target 0');
    xlabel('ao0 [V]'); ylabel('FRFRdot_hat mean [ns/s]');
    title(sprintf('Verify-A: FRFRdot vs ao0 (ao1 fixed=%.3fV), ao0*≈%.3fV', ao1_fixed, ao0_star));

    figure('Name','Verify-A: FRFRdot dispersion','NumberTitle','off');
    errorbar(ao0_V, dot_mean, dot_std, 'o-', 'LineWidth', 1.2); grid on; hold on;
    yline(0,'r--','Target 0');
    xlabel('ao0 [V]'); ylabel('FRFRdot_hat mean ± std [ns/s]');
    title('Verify-A: Mean ± Std (per ao0)');

    %% ---------- Return ----------
    result = struct();
    result.csv_summary = summary_name;
    result.csv_detail  = detail_name;
    result.fit = struct('a',a,'b',b,'ao0_star',ao0_star);
    result.params = struct('Ts_target',Ts_target,'window_s',window_s,'settle_s',settle_s, ...
        'T_period_ns',T_period_ns,'FRFR_is_seconds',FRFR_is_seconds, ...
        'ao1_fixed',ao1_fixed,'ao0_list',ao0_list,'alpha',alpha,'use_ema',use_ema, ...
        'ip',ip);
end

% ---------------- helpers (same file) ----------------

function [frfr_meas_ns, frfr_w_ns, dy_w_ns, dt_s, dot_nsps] = measure_wrapped_dot_series(dev, Ts_target, window_s, T_period_ns, FRFR_is_seconds)
    % Measure wrapped FRFR and estimate derivative using wrapped delta (local unwrap)
    t0 = tic;

    prev_frfr_w = NaN;
    prev_t = NaN;

    frfr_meas_ns = [];
    frfr_w_ns    = [];
    dy_w_ns      = [];
    dt_s         = [];
    dot_nsps     = [];

    while toc(t0) < window_s
        % Read FRFR
        writeline(dev, "MEAS:ADV:P3:VAL?");
        val = str2double(readline(dev));
        if isnan(val)
            pause(Ts_target);
            continue;
        end

        if FRFR_is_seconds
            frfr_meas = val * 1e9; % [ns]
        else
            frfr_meas = val;       % already [ns]
        end

        % Normalize measurement into [-T/2, T/2)
        frfr_w = wrapToHalfPeriod(frfr_meas, T_period_ns);

        t_now = toc(t0);

        frfr_meas_ns(end+1,1) = frfr_meas; %#ok<AGROW>
        frfr_w_ns(end+1,1)    = frfr_w;    %#ok<AGROW>

        if ~isnan(prev_frfr_w)
            dt = t_now - prev_t;

            % WRAPPED DELTA: fixes boundary jumps (e.g., 49 -> -47 becomes +4)
            dy = wrapToHalfPeriod(frfr_w - prev_frfr_w, T_period_ns);

            dot = dy / dt; % [ns/s]

            dy_w_ns(end+1,1)  = dy;  %#ok<AGROW>
            dt_s(end+1,1)     = dt;  %#ok<AGROW>
            dot_nsps(end+1,1) = dot; %#ok<AGROW>
        end

        prev_frfr_w = frfr_w;
        prev_t      = t_now;

        pause(Ts_target);
    end

    % Align lengths: dy/dt/dot are one shorter than frfr series
    % Here we keep them as-is (caller expects dot_hat length = numel(dot_nsps)).
    if isempty(dot_nsps)
        dy_w_ns  = zeros(0,1);
        dt_s     = zeros(0,1);
        dot_nsps = zeros(0,1);
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
    % Map any real x into [-T/2, +T/2)
    z = mod(x + T/2, T) - T/2;
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0, safe_ao1)
    % Safe shutdown on exit/error
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
