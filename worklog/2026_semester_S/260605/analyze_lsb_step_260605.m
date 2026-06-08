function R = analyze_lsb_step_260605(csv_file)
%====================================================================
% frfr_lsb_step の CSV から、最小ステップ応答を解析・作図する
% （ハード不要。測定済み CSV を後処理するだけ）
%
%   ・各段(10s窓)の FRFR(unwrapped) を直線フィット → 傾き[ns/s]
%     （段の頭 settle_s 秒は整定として除外）
%   ・傾き vs 電圧増分 の直線フィット → 1ステップ(=1LSB)あたりの
%     傾き変化と 推定K[ns/(V*s)] を算出
%   ・図2枚を保存:
%       <csv>_ts.png    … FRFR と ao0 の時系列
%       <csv>_slope.png … 傾き vs 電圧増分（主結果）
%
%   使い方:
%     R = analyze_lsb_step_260605("frfr_lsb_step_20260605_192111.csv");
%====================================================================
    if nargin < 1 || isempty(csv_file)
        error('CSVファイル名を指定してください。');
    end
    settle_s = 1.5;
    lsb_V = 20/65536;          % USB-6211 1 LSB [V]

    T = readtable(csv_file);
    ph = string(T.phase);
    isst = (ph == "stair");
    lev = T.level_k(isst);
    t   = T.time_s(isst);
    y   = T.frfr_unwrapped_ns(isst);
    ao  = T.ao0_V(isst);

    levels = unique(lev(~isnan(lev)))';
    slope  = nan(size(levels));
    aolvl  = nan(size(levels));
    for ii = 1:numel(levels)
        m  = (lev == levels(ii));
        tk = t(m); yk = y(m);
        aolvl(ii) = mean(ao(m));
        keep = tk > (min(tk) + settle_s);
        if sum(keep) >= 3
            p = polyfit(tk(keep), yk(keep), 1);
            slope(ii) = p(1);
        end
    end

    % 実際の1ステップ電圧増分（commanded ao0 の段間差の中央値）
    dV_step = median(diff(aolvl));
    dV_lvl  = (levels - levels(1)) * dV_step;     % 基準からの増分[V]

    good = ~isnan(slope);
    pf = polyfit(levels(good), slope(good), 1);
    slope_per_step = pf(1);                 % [ns/s] / 段
    baseline       = pf(2);                 % 段0の傾き [ns/s]
    K_est          = slope_per_step / dV_step;
    nlsb_per_step  = dV_step / lsb_V;        % 1段が何LSBか（≒1のはず）

    fprintf('=== %s ===\n', csv_file);
    fprintf('1段の電圧増分 = %.4f mV (= %.2f LSB)\n', dV_step*1e3, nlsb_per_step);
    fprintf('1段あたり FRFR傾き変化 = %.4g ns/s  (10s窓で %.4g ns)\n', ...
        slope_per_step, slope_per_step*10);
    fprintf('1 LSB あたり          = %.4g ns/s\n', slope_per_step/nlsb_per_step);
    fprintf('推定 K = %.4g ns/(V*s) | 段0傾き = %.3f ns/s\n', K_est, baseline);

    % --- 図1: 時系列（全体: lock + stair）---
    f1 = figure('Name','lsb step: timeseries','NumberTitle','off','Position',[80 80 900 480]);
    tiledlayout(2,1,'TileSpacing','compact');
    nexttile; plot(T.time_s, T.frfr_unwrapped_ns, 'b-'); grid on;
    ylabel('FRFR unwrapped [ns]'); title(['最小ステップ応答  ' csv_file], 'Interpreter','none');
    nexttile; plot(T.time_s, T.ao0_V*1e3, 'r-'); grid on;
    xlabel('Time [s]'); ylabel('ao0 [mV]');
    exportgraphics(f1, strrep(csv_file,'.csv','_ts.png'), 'Resolution',300);

    % --- 図2: 傾き vs 電圧増分（主結果）---
    f2 = figure('Name','lsb step: slope','NumberTitle','off','Position',[100 100 720 460]);
    plot(dV_lvl*1e3, slope, 'o-'); hold on;
    plot(dV_lvl*1e3, polyval(pf, levels), 'r--');
    grid on; xlabel('電圧増分 ΔV (段0基準) [mV]'); ylabel('FRFR傾き [ns/s]');
    title(sprintf('1段(%.3fmV=%.1fLSB) あたり %.3g ns/s 変化, K≈%.0f ns/(V·s)', ...
        dV_step*1e3, nlsb_per_step, slope_per_step, K_est));
    exportgraphics(f2, strrep(csv_file,'.csv','_slope.png'), 'Resolution',300);

    R = struct('csv',csv_file, 'levels',levels, 'slope',slope, 'aolvl',aolvl, ...
        'dV_step',dV_step, 'slope_per_step',slope_per_step, 'K_est',K_est, ...
        'baseline',baseline, 'lsb_V',lsb_V);
    fprintf('図保存: %s , %s\n', strrep(csv_file,'.csv','_ts.png'), strrep(csv_file,'.csv','_slope.png'));
end
