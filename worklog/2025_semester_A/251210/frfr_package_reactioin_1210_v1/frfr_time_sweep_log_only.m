function frfr_time_sweep_log_only()
% FRFR time sweep logging only
% ΔV=0.5V 固定、T を 0.1〜5s で sweep し、
% 各 run ごとに FRFR 時系列を CSV に保存する。
%
% 後で ΔFRFR vs T の解析・プロットを別スクリプトで行う前提。

    clear; clc;

    %% ---- 実験パラメータ -----------------------------------------
    DeltaV = 0.5;   % [V] パルス振幅（固定）

    % [s] パルス幅のリスト（0.1〜5s）
    T_list = [0.1, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0, 3.25, 3.5, 3.75, 4.0, 4.25, 5.0];

    baseline_time = 40;   % [s] パルス前に FB で安定化させる時間
    post_time     = 40;   % [s] パルス後に観測する時間

    interval_wait = 30;   % [s] Run 間インターバル（この間は 0V）

    %% ---- sweep 実行 ---------------------------------------------
    nRuns = numel(T_list);
    log_files = strings(nRuns, 1);

    fprintf("=== FRFR time sweep logging start ===\n");
    fprintf("DeltaV = %.3f V, T_list = [", DeltaV);
    fprintf(" %.2f", T_list);
    fprintf(" ] s\n");

    for k = 1:nRuns
        Tpulse = T_list(k);
        fprintf("\n=== Run %d / %d : Tpulse = %.3f s ===\n", k, nRuns, Tpulse);

        log_files(k) = frfr_single_pulse_time_log( ...
            DeltaV, Tpulse, baseline_time, post_time);

        fprintf("Run %d ログ保存完了: %s\n", k, log_files(k));

        if k < nRuns
            fprintf("インターバル開始: ao0/ao1 を 0V に戻して %d s 待機します...\n", ...
                interval_wait);
            pause(interval_wait);
        end
    end

    %% ---- サマリ CSV（どの Run でどのファイルか） --------------
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    summary_name = sprintf('frfr_time_sweep_runlist_%s.csv', timestamp);

    T = table((1:nRuns).', T_list(:), repmat(DeltaV, nRuns, 1), log_files, ...
              'VariableNames', {'RunIndex','Tpulse_s','DeltaV_V','LogFile'});

    writetable(T, summary_name);

    fprintf("\n=== time sweep logging 完了 ===\n");
    fprintf("Run リストを保存しました: %s\n", summary_name);
end
