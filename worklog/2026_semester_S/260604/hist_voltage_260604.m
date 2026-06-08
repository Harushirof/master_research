function hist_voltage_260604(seg_target, csv_file)
%====================================================================
% 260604 本番ランの指定区間における制御電圧 ao0 のヒストグラム
%
%   既定は gentle（20〜25分, 全部入り条件）。
%   区間名を変えれば他区間（kijun/HOLD1/p3slow/p4avg/gentle）にも使える。
%
%   PNG 保存: 260604_hist_ao0_<区間>.png
%
%   使い方（Current Folder を 260604 に）:
%     hist_voltage_260604();            % gentle（20-25分）
%     hist_voltage_260604('p4avg');     % 別区間
%====================================================================
    if nargin < 1 || isempty(seg_target), seg_target = 'gentle'; end
    if nargin < 2 || isempty(csv_file)
        csv_file = 'frfr_phase2_seq_20260604_183831.csv';
    end
    seg_target = string(seg_target);

    T   = readtable(csv_file);
    seg = string(T.segment);
    idx = (seg == seg_target);
    if ~any(idx)
        error('区間 "%s" が見つかりません。', seg_target);
    end
    u = T.ao0_V(idx);
    t = T.time_s(idx) / 60;     % [min]

    % --- 統計 ---
    m  = mean(u);  sd = std(u);  n = numel(u);
    fprintf('=== %s 区間 ao0 [V] ===\n', seg_target);
    fprintf('  n=%d | 時間 %.1f〜%.1f min\n', n, min(t), max(t));
    fprintf('  mean=%.4f V | std=%.5f V | min=%.4f | max=%.4f | range=%.4f\n', ...
        m, sd, min(u), max(u), max(u)-min(u));

    % --- ヒストグラム ---
    fig = figure('Name',['hist ao0 ' char(seg_target)],'NumberTitle','off', ...
                 'Position',[100 100 720 440]);
    histogram(u, 'NumBins', 30, 'FaceColor',[0.2 0.4 0.8]); hold on;
    xline(m, 'r-',  sprintf('mean %.4f V', m), 'LineWidth',1.5);
    xline(m+sd,'r--'); xline(m-sd,'r--', sprintf('±1σ (%.4f V)', sd));
    grid on; box on;
    xlabel('Control voltage  ao0 [V]'); ylabel('count');
    title(sprintf('%s 区間の制御電圧ヒストグラム（n=%d, std=%.4f V）', ...
        seg_target, n, sd), 'Interpreter','none');

    out = sprintf('260604_hist_ao0_%s.png', seg_target);
    exportgraphics(fig, out, 'Resolution', 300);
    fprintf('保存: %s\n', out);
end
