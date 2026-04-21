function plot_pulse_area_sweep()
% frfr_pulse_area_sweep_summary_20251208_171758.csv を読み込み、
% ・Runごとの ΔFRFR のバラつき
% ・ΔV vs ΔFRFR
% ・T_pulse vs ΔFRFR
% を図示する。

    %% ===== ファイル名（必要なら書き換え） =========================
    summary_csv = 'frfr_pulse_area_sweep_summary_20251208_171758.csv';

    %% ===== 読み込み =================================================
    T = readtable(summary_csv);

    % 想定している列:
    %   DeltaV_V
    %   Tpulse_s
    %   DeltaFRFR_ns
    %   Area_Vs
    %   log_csv_name
    if ~all(ismember({'DeltaV_V','Tpulse_s','DeltaFRFR_ns'}, T.Properties.VariableNames))
        error('期待する列 DeltaV_V / Tpulse_s / DeltaFRFR_ns が CSV にありません。');
    end

    dv   = T.DeltaV_V;
    tp   = T.Tpulse_s;
    dfr  = T.DeltaFRFR_ns;
    area = T.Area_Vs;

    nRuns = height(T);
    run_idx = (1:nRuns).';

    fprintf("Loaded %d runs from %s\n", nRuns, summary_csv);
    disp(table(run_idx, dv, tp, area, dfr, ...
        'VariableNames',{'Run','DeltaV_V','Tpulse_s','Area_Vs','DeltaFRFR_ns'}));

    %% ===== 図1: Run順の ΔFRFR 推移 =================================
    figure('Name','Run vs ΔFRFR','NumberTitle','off');
    plot(run_idx, dfr, '-o', 'LineWidth', 1.5, 'MarkerSize', 8);
    grid on;
    xlabel('Run index');
    ylabel('\Delta FRFR [ns]');
    title('\Delta FRFR per Run (Area \approx const.)');

    % x軸に (ΔV, T) のラベルを付けると分かりやすい
    xticks(run_idx);
    xlabels = strings(nRuns,1);
    for k = 1:nRuns
        xlabels(k) = sprintf('V=%.2f, T=%.2f', dv(k), tp(k));
    end
    xticklabels(xlabels);
    xtickangle(30);  % 斜めにして見やすく

    %% ===== 図2: ΔV vs ΔFRFR ========================================
    figure('Name','DeltaV vs ΔFRFR','NumberTitle','off');
    scatter(dv, dfr, 80, 'filled'); grid on;
    xlabel('\Delta V [V]');
    ylabel('\Delta FRFR [ns]');
    title('\Delta FRFR vs \Delta V  (Area fixed)');

    % 参考として線を結んでみる（任意）
    hold on;
    plot(dv, dfr, '--');

    %% ===== 図3: T_pulse vs ΔFRFR ===================================
    figure('Name','Tpulse vs ΔFRFR','NumberTitle','off');
    scatter(tp, dfr, 80, 'filled'); grid on;
    xlabel('T_{pulse} [s]');
    ylabel('\Delta FRFR [ns]');
    title('\Delta FRFR vs T_{pulse}  (Area fixed)');

    hold on;
    plot(tp, dfr, '--');

    %% ===== 簡単な統計出力 ==========================================
    fprintf('\n=== ΔFRFR 統計 ===\n');
    fprintf('  mean(ΔFRFR) = %.3f ns\n', mean(dfr, 'omitnan'));
    fprintf('  std(ΔFRFR)  = %.3f ns\n', std(dfr,  'omitnan'));
end
