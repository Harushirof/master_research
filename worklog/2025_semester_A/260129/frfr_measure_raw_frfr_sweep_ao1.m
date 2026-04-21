function result = frfr_measure_raw_frfr_sweep_ao1()
%====================================================================
% Raw FRFR measurement vs ao1 sweep (NO unwrap / NO normalization)
% Sweep: ao1 = 1.20 : 0.05 : 1.40 [V]
% Keep:  ao0 = ao0_const [V] fixed
%
% Logs:
%   - summary CSV: mean/std/median FRFR per ao1
%   - detail  CSV: time series raw FRFR per ao1



%
% Notes:
%   - "Raw FRFR" means: use the instrument value as-is, only unit conversion for convenience.
%   - If the scope returns seconds, we also store ns (=sec*1e9).
%   - onCleanup sets NI outputs to 0 V.
%====================================================================

    %% ---- User params ----
    ip  = "192.168.1.61";

    ao0_const = 1.54;                 % [V] fixed
    ao1_list  = 1.20:0.05:1.40;       % [V] sweep

    settle_s  = 2.0;                  % [s] wait after setting ao1
    window_s  = 10.0;                 % [s] measurement duration per point
    Ts        = 0.30;                 % [s] sampling interval (pause)

    v_min = 0.0; v_max = 5.0;

    % If "MEAS:ADV:P3:VAL?" returns seconds, set true.
    % If it already returns ns, set false.
    FRFR_is_seconds = true;

    SAFE_AO0_V = 0.0;
    SAFE_AO1_V = 0.0;

    %% ---- Init DAQ / Scope ----
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev, SAFE_AO0_V, SAFE_AO1_V)); %#ok<NASGU>

    fprintf("=== Raw FRFR sweep ao1 ===\n");
    fprintf("Function path: %s\n", which(mfilename));
    fprintf("ao0_const=%.4f V | ao1=[%.2f..%.2f] step %.2f V | window=%.1f s | Ts=%.2f s\n", ...
        ao0_const, ao1_list(1), ao1_list(end), ao1_list(2)-ao1_list(1), window_s, Ts);

    %% ---- Prepare logs ----
    nP = numel(ao1_list);

    ao1_V      = zeros(nP,1);
    frfr_mean  = zeros(nP,1);
    frfr_std   = zeros(nP,1);
    frfr_median= zeros(nP,1);
    N          = zeros(nP,1);

    d_point_idx = [];
    d_ao1_V     = [];
    d_t_s       = [];
    d_frfr_raw  = [];   % instrument raw value (sec or ns)
    d_frfr_ns   = [];   % converted ns (if sec -> ns, else same)

    %% ---- Sweep ----
    for i = 1:nP
        ao1 = clamp(ao1_list(i), v_min, v_max);
        ao0 = clamp(ao0_const,  v_min, v_max);

        % Apply outputs
        outputSingleScan(s, [ao0, ao1]);
        pause(settle_s);

        % Measure for window_s
        t0 = tic;
        t_series = [];
        raw_series = [];
        ns_series  = [];

        while toc(t0) < window_s
            t_now = toc(t0);

            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                val = str2double(readline(dev));
            catch ME
                warning("FRFR read error at ao1=%.3f V: %s", ao1, ME.message);
                val = NaN;
            end

            if ~isnan(val)
                if FRFR_is_seconds
                    frfr_ns = val * 1e9;
                else
                    frfr_ns = val;
                end

                t_series(end+1,1)   = t_now;   %#ok<AGROW>
                raw_series(end+1,1) = val;     %#ok<AGROW>
                ns_series(end+1,1)  = frfr_ns; %#ok<AGROW>
            end

            pause(Ts);
        end

        ao1_V(i)       = ao1;
        frfr_mean(i)   = mean(ns_series, 'omitnan');
        frfr_std(i)    = std(ns_series,  'omitnan');
        frfr_median(i) = median(ns_series, 'omitnan');
        N(i)           = numel(ns_series);

        fprintf("[%-2d/%-2d] ao1=%.3f V | FRFR(ns) mean=%.3f | med=%.3f | std=%.3f | N=%d\n", ...
            i, nP, ao1, frfr_mean(i), frfr_median(i), frfr_std(i), N(i));

        % Append detail logs
        m = numel(ns_series);
        d_point_idx = [d_point_idx; repmat(i, m, 1)]; %#ok<AGROW>
        d_ao1_V     = [d_ao1_V;     repmat(ao1, m, 1)]; %#ok<AGROW>
        d_t_s       = [d_t_s;       t_series]; %#ok<AGROW>
        d_frfr_raw  = [d_frfr_raw;  raw_series]; %#ok<AGROW>
        d_frfr_ns   = [d_frfr_ns;   ns_series]; %#ok<AGROW>
    end

    %% ---- Save CSVs ----
    timestamp   = datestr(now,'yyyymmdd_HHMMSS');
    summary_csv = sprintf("frfr_raw_sweep_ao1_summary_%s.csv", timestamp);
    detail_csv  = sprintf("frfr_raw_sweep_ao1_detail_%s.csv",  timestamp);

    summary_tbl = table(ao1_V, frfr_mean, frfr_median, frfr_std, N, ...
        'VariableNames', {'ao1_V','frfr_ns_mean','frfr_ns_median','frfr_ns_std','N'});

    detail_tbl  = table(d_point_idx, d_ao1_V, d_t_s, d_frfr_raw, d_frfr_ns, ...
        'VariableNames', {'point_idx','ao1_V','t_local_s','frfr_raw','frfr_ns'});

    writetable(summary_tbl, summary_csv);
    writetable(detail_tbl,  detail_csv);

    fprintf("Saved summary: %s\n", summary_csv);
    fprintf("Saved detail : %s\n", detail_csv);

    %% ---- Plot ----
    figure('Name','Raw FRFR (ns) vs ao1','NumberTitle','off');
    errorbar(ao1_V, frfr_mean, frfr_std, 'o-', 'LineWidth', 1.2);
    grid on;
    xlabel('ao1 [V]'); ylabel('FRFR [ns] (raw, no unwrap)');
    title('Raw FRFR vs ao1 (mean ± std)');

    %% ---- Return ----
    result = struct();
    result.summary_csv = summary_csv;
    result.detail_csv  = detail_csv;
    result.params = struct( ...
        'ao0_const', ao0_const, 'ao1_list', ao1_list, ...
        'settle_s', settle_s, 'window_s', window_s, 'Ts', Ts, ...
        'FRFR_is_seconds', FRFR_is_seconds, 'ip', ip);
end

% ---------------- helpers (same file) ----------------
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
