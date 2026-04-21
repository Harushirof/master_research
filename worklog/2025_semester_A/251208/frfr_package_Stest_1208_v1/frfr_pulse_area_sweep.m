function frfr_pulse_area_sweep()
%====================================================================
% パルス面積 A0 = 0.5 [V·s] を一定にしつつ、
%   (ΔV, T_pulse) を 5 パターン変えながら
%   frfr_pulse_after_fb_single_run を実行するスクリプト
%
% 各 Run 間では single_run が cleanupDAQ により ao0/ao1 を0Vに戻すため、
% インターバル中は電圧が一切かからない。
%====================================================================

    %% --- パラメータ設定 -----------------------------------------
    A0           = 0.5;     % [V·s] パルス面積
    n_runs       = 5;
    interval_sec = 120;     % [s] Run間インターバル
    t_stable     = 60;      % [s] パルス前の安定化時間

    % ΔV候補（最大 5V）
    V_candidates = [0.5, 1.0, 2.0, 3.0, 5.0];
    T_candidates = A0 ./ V_candidates;   % T = A0 / ΔV

    % s >= 0.1 s の制約
    valid_idx = T_candidates >= 0.1;
    V_list = V_candidates(valid_idx);
    T_list = T_candidates(valid_idx);

    % 5パターンに制限
    if numel(V_list) < n_runs
        error('条件を満たす (ΔV, T) の組が %d 個しかありません。', numel(V_list));
    end
    V_list = V_list(1:n_runs);
    T_list = T_list(1:n_runs);

    %% --- 結果用配列 ---------------------------------------------
    dv_all  = zeros(n_runs,1);
    tp_all  = zeros(n_runs,1);
    dfr_all = zeros(n_runs,1);
    log_all = strings(n_runs,1);

    fprintf("=== Pulse Area Sweep Start (A0 = %.3f V·s) ===\n", A0);

    %% --- メインループ -------------------------------------------
    for k = 1:n_runs
        dv = V_list(k);
        tp = T_list(k);

        fprintf("\n=== Run %d / %d ===\n", k, n_runs);
        fprintf("ΔV = %.3f V, T_pulse = %.3f s (Area = %.3f V·s)\n", dv, tp, dv*tp);

        % --- 単発実験を実行 (内部で FB + パルス + 0Vリセットまで行う) ---
        result = frfr_pulse_after_fb_single_run(dv, tp, t_stable);

        dv_all(k)  = dv;
        tp_all(k)  = tp;
        dfr_all(k) = result.delta_frfr;
        log_all(k) = string(result.log_csv);

        % --- インターバル（この間は電圧0V） ---
        if k < n_runs
            fprintf("Waiting %d s before next run...\n", interval_sec);
            pause(interval_sec);
        end
    end

    %% --- サマリCSV保存 ------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    summary_filename = sprintf("frfr_pulse_area_sweep_summary_%s.csv", timestamp);

    T = table(dv_all, tp_all, dfr_all, dv_all.*tp_all, log_all, ...
              'VariableNames', ...
              {'DeltaV_V','Tpulse_s','DeltaFRFR_ns','Area_Vs','log_csv_name'});

    writetable(T, summary_filename);

    fprintf("\n=== Sweep finished ===\n");
    fprintf("Summary saved: %s\n", summary_filename);
end
