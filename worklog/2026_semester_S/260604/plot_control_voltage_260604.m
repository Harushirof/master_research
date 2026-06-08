function plot_control_voltage_260604(csv_file)
%====================================================================
% 260604 本番ランの制御電圧 ao0 の時系列グラフ
%   ・横軸 時間[min]、縦軸 制御電圧 ao0[V]
%   ・5区間（kijun/HOLD1/p3slow/p4avg/gentle）の境界を点線＋ラベルで表示
%   ・HOLD1（無制御＝電圧固定）区間を薄く塗って明示
%   ・PNG 保存: 260604_control_voltage.png
%
%   使い方（Current Folder を 260604 に）:
%     plot_control_voltage_260604();
%====================================================================
    if nargin < 1 || isempty(csv_file)
        csv_file = 'frfr_phase2_seq_20260604_183831.csv';
    end

    T   = readtable(csv_file);
    t   = T.time_s / 60;          % [min]
    u   = T.ao0_V;                % [V]
    seg = string(T.segment);

    % --- 区間の開始/終了・名前を検出 ---
    isStart  = [true; seg(2:end) ~= seg(1:end-1)];
    starts   = find(isStart);
    segNames = seg(starts);
    segBeg   = t(starts);
    segEnd   = [t(starts(2:end)-1); t(end)];

    fig = figure('Name','control voltage','NumberTitle','off', ...
                 'Position',[100 100 900 380]);
    hold on;

    % --- HOLD（無制御）区間を薄く塗る ---
    for k = 1:numel(segNames)
        if startsWith(segNames(k), "HOLD")
            try
                xregion(segBeg(k), segEnd(k), 'FaceColor',[0.85 0.85 0.85], ...
                        'FaceAlpha',0.5);
            catch
                yl = [min(u) max(u)];
                patch([segBeg(k) segEnd(k) segEnd(k) segBeg(k)], ...
                      [yl(1) yl(1) yl(2) yl(2)], [0.85 0.85 0.85], ...
                      'EdgeColor','none','FaceAlpha',0.5);
            end
        end
    end

    % --- 制御電圧 ---
    plot(t, u, 'b-', 'LineWidth', 1.1);

    % --- 区間境界＋ラベル ---
    ytop = max(u) + 0.02*range(u) + 0.02;
    for k = 1:numel(segNames)
        if k > 1, xline(segBeg(k), 'k:', 'LineWidth', 1.0); end
        text(segBeg(k) + 0.2, ytop, segNames(k), ...
             'FontSize', 9, 'VerticalAlignment','bottom', 'Interpreter','none');
    end

    grid on; box on;
    xlabel('Time [min]'); ylabel('Control voltage  ao0 [V]');
    title('FB制御電圧 ao0 の時系列（260604 本番ラン, 灰=HOLD無制御）');
    xlim([min(t) max(t)]);
    ylim([min(u)-0.02*range(u)-0.01, ytop + 0.05*range(u) + 0.02]);

    exportgraphics(fig, '260604_control_voltage.png', 'Resolution', 300);
    fprintf('保存: 260604_control_voltage.png\n');

    % --- 区間ごとの電圧レンジを参考表示 ---
    fprintf('\n区間別 ao0 [V]（min / max / 移動量Σ|Δu|）:\n');
    for k = 1:numel(segNames)
        idx = t >= segBeg(k) & t <= segEnd(k);
        uu  = u(idx);
        travel = sum(abs(diff(uu)));
        fprintf('  %-7s  %.3f 〜 %.3f   Σ|Δu|=%.3f\n', ...
            segNames(k), min(uu), max(uu), travel);
    end
end
