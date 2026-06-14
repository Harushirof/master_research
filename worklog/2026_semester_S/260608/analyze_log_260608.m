function R = analyze_log_260608(log_csv)
%====================================================================
% 260608 実験ログ(オシロFRFR)の自動解析・作図  ── 制御側の評価
%
%   gainsweep / model どちらのログ CSV でもそのまま解析できる汎用版。
%   ハード不要。記録済み CSV を後処理して図とサマリを自動保存するだけ。
%
%   入力: 実験スクリプトが出力した log CSV
%     （frfr_gainsweep_*.csv / frfr_model_*.csv）
%     共通列を使用: time_s, segment, mode, frfr_unwrapped_ns,
%                   e_phase_ns, freq_err_ns_per_s, delta_u_V, ao0_V
%
%   評価指標（区間ごと）:
%     ・終端60s std [ns]   … ハンチング（小さいほど良い＝勝ち筋）
%     ・電圧移動量 Σ|du| [V] … 動かさないほど静か
%     ・mean|e| [ns]       … 目標への寄り
%
%   自動保存（<base>=log_csv からの規約名）:
%     <base>_timeseries.png … FRFR(上)＋制御電圧(下), 目標線・区間境界つき
%     <base>_freqerr.png    … 周波数誤差 df の時系列（ハンチング可視化）
%     <base>_segstd.png     … 区間別 終端60s std 棒グラフ（HOLD基準線）
%     <base>_logsummary.csv … 区間別 std / travel / mean|e| / mean ao0
%
%   使い方（Current Folder を 260608 に）:
%     R = analyze_log_260608("frfr_gainsweep_20260608_140000.csv");
%     R = analyze_log_260608("frfr_model_20260608_141000.csv");
%====================================================================
    if nargin < 1 || isempty(log_csv)
        error('ログCSVファイル名を指定してください。');
    end
    base = char(strrep(string(log_csv), '.csv', ''));
    win_std = 60;     % 終端std評価窓 [s]

    T = readtable(log_csv);
    t    = T.time_s;
    seg  = string(T.segment);
    mode = string(T.mode);
    unw  = T.frfr_unwrapped_ns;
    e    = T.e_phase_ns;
    df   = T.freq_err_ns_per_s;
    du   = T.delta_u_V;
    ao0  = T.ao0_V;

    % 目標線の復元（target = frfr_unw + e, FB/MODEL行の中央値）
    isfb = (mode ~= "HOLD");
    if any(isfb)
        target = median(unw(isfb) + e(isfb), 'omitnan');
    else
        target = NaN;
    end

    %% === 区間ごとの指標（出現順）======================================
    [segU, ia] = unique(seg, 'stable');
    nseg = numel(segU);
    seg_t0 = nan(nseg,1); seg_t1 = nan(nseg,1);
    seg_mode = strings(nseg,1);
    std_term = nan(nseg,1); travel = nan(nseg,1);
    mean_abs_e = nan(nseg,1); mean_ao0 = nan(nseg,1);
    for i = 1:nseg
        m = (seg == segU(i));
        seg_t0(i) = min(t(m)); seg_t1(i) = max(t(m));
        seg_mode(i) = mode(find(m,1));
        tail = m & (t > seg_t1(i) - win_std);
        if sum(tail) > 3, std_term(i) = std(unw(tail)); end
        travel(i)     = sum(abs(du(m)), 'omitnan');
        mean_abs_e(i) = mean(abs(e(m)), 'omitnan');
        mean_ao0(i)   = mean(ao0(m), 'omitnan');
    end

    %% === サマリ表示 + CSV =============================================
    fprintf('=== %s ===\n', log_csv);
    fprintf('目標 FRFR ≈ %.2f ns | 区間数 %d\n\n', target, nseg);
    fprintf('%-7s %-6s %10s %12s %10s\n', 'seg','mode','std[ns]','travel[V]','mean|e|');
    for i = 1:nseg
        fprintf('%-7s %-6s %10.3f %12.4f %10.3f\n', ...
            segU(i), seg_mode(i), std_term(i), travel(i), mean_abs_e(i));
    end
    [~, ibest] = min(std_term);
    fprintf('\n>>> 終端std 最小（勝ち筋）: %s [%s]  std=%.3f ns\n', ...
        segU(ibest), seg_mode(ibest), std_term(ibest));
    ih = find(seg_mode=="HOLD", 1);
    if ~isempty(ih)
        fprintf('    HOLD基準 std=%.3f ns（無制御）\n', std_term(ih));
    end

    Tbl = table(segU, seg_mode, seg_t0, seg_t1, std_term, travel, mean_abs_e, mean_ao0, ...
        'VariableNames', {'segment','mode','t_start_s','t_end_s', ...
        'std_terminal_ns','volt_travel_V','mean_abs_e_ns','mean_ao0_V'});
    sum_csv = [base '_logsummary.csv'];
    writetable(Tbl, sum_csv);
    fprintf('サマリ: %s\n', sum_csv);

    %% === 図1: 時系列（FRFR + 電圧）====================================
    f1 = figure('Name','log: timeseries','NumberTitle','off','Visible','off','Position',[80 80 950 560]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile;
    plot(t, unw, 'b-', 'LineWidth', 1.0); hold on; grid on;
    if ~isnan(target), yline(target, 'r--', sprintf('Target %.1f', target)); end
    ymax = max(unw,[],'omitnan');
    for i = 1:nseg
        xline(seg_t0(i), 'k:');
        text(seg_t0(i), ymax, sprintf(' %s', segU(i)), ...
            'Rotation',90, 'VerticalAlignment','top', 'FontSize',8, 'Interpreter','none');
    end
    ylabel('FRFR (unwrapped) [ns]');
    title(['FRFR(上) と 制御電圧(下)  ' base], 'Interpreter','none');
    nexttile;
    plot(t, ao0*1e3, 'r-'); grid on;
    for i = 1:nseg, xline(seg_t0(i), 'k:'); end
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(f1, [base '_timeseries.png'], 'Resolution', 300);
    close(f1);

    %% === 図2: 周波数誤差 df の時系列 ==================================
    f2 = figure('Name','log: freq err','NumberTitle','off','Visible','off','Position',[100 100 900 380]);
    plot(t, df, '-', 'Color',[0.1 0.5 0.2]); hold on; grid on;
    yline(0, 'k:');
    for i = 1:nseg, xline(seg_t0(i), 'k:'); end
    xlabel('Time [s]'); ylabel('freq err dFRFR/dt [ns/s]');
    title(['周波数誤差の時系列（0付近で安定＝同期）  ' base], 'Interpreter','none');
    exportgraphics(f2, [base '_freqerr.png'], 'Resolution', 300);
    close(f2);

    %% === 図3: 区間別 終端60s std 棒グラフ（主結果）===================
    f3 = figure('Name','log: seg std','NumberTitle','off','Visible','off','Position',[120 120 760 460]);
    b = bar(std_term); grid on;
    set(gca, 'XTickLabel', cellstr(segU), 'TickLabelInterpreter','none');
    ylabel('終端60s FRFR std [ns]');
    title(sprintf('区間別ハンチング（小さいほど良い） 最小=%s', segU(ibest)), 'Interpreter','none');
    if ~isempty(ih)
        yline(std_term(ih), 'r--', sprintf('HOLD %.3f', std_term(ih)));
    end
    % 数値ラベル
    xt = 1:nseg;
    text(xt, std_term, compose('%.3f', std_term), ...
        'HorizontalAlignment','center', 'VerticalAlignment','bottom', 'FontSize',8);
    exportgraphics(f3, [base '_segstd.png'], 'Resolution', 300);
    close(f3);

    fprintf('図保存: %s_timeseries.png / _freqerr.png / _segstd.png\n', base);

    %% === 結果構造体 ===================================================
    R = struct('log_csv',log_csv, 'target',target, 'segment',{cellstr(segU)}, ...
        'mode',{cellstr(seg_mode)}, 'std_terminal_ns',std_term, ...
        'volt_travel_V',travel, 'mean_abs_e_ns',mean_abs_e, ...
        'best_segment',char(segU(ibest)), 'summary_csv',sum_csv);
end
