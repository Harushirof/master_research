function analyze_frfr_pulse_sweep()
%====================================================================
% パルスSweep実験の解析スクリプト
%
% 入力:
%   - frfr_pulse_sweep_summary_*.csv
%       delta_v_V     : 各Runのパルス振幅 [V]
%       T_pulse_s     : パルス幅 [s] (なければ 1s と仮定)
%       log_csv_name  : 各Runの生ログCSV名
%
%   - 各Runの生ログCSV (log_csv_name で指定)
%       time_s        : 時刻 [s]
%       frfr_ns       : FRFR [ns]
%       phase         : 0: FB安定化, 1: パルス, 2: パルス後
%
% 処理:
%   1. phase==1 からパルス区間 [t_start, t_end] を自動検出
%   2. パルス前後で「除外マージン＋10秒窓」で FRFR を平均
%   3. ΔFRFR = after_mean - before_mean を算出
%   4. K = ΔFRFR / (ΔV * T_pulse) を算出
%   5. ΔV vs ΔFRFR の散布図＋一次回帰＋R^2 を表示
%   6. K vs ΔV の散布図を表示（補助）
%   7. 解析サマリCSVを書き出し
%====================================================================

    %% ===== 解析対象のサマリCSV名（必要なら変更） =====================
    summary_csv = 'frfr_pulse_sweep_summary_20251205_192817.csv';

    %% ===== パルス前後の平均窓・マージン [s] ==========================
    pre_margin   = 3;    % パルス直前の除外区間
    post_margin  = 3;    % パルス直後の除外区間
    pre_window   = 10;   % パルス前の平均窓幅
    post_window  = 10;   % パルス後の平均窓幅

    %% ===== サマリCSV読込 =============================================
    S = readtable(summary_csv);

    if ~ismember('delta_v_V', S.Properties.VariableNames)
        error('summary CSV に delta_v_V 列がありません。');
    end
    if ~ismember('log_csv_name', S.Properties.VariableNames)
        error('summary CSV に log_csv_name 列がありません。');
    end

    delta_v_list = S.delta_v_V;
    log_names    = S.log_csv_name;

    if ismember('T_pulse_s', S.Properties.VariableNames)
        T_pulse_list = S.T_pulse_s;
    else
        T_pulse_list = ones(height(S),1);    % 無ければ 1s と仮定
    end

    nRuns = height(S);

    %% ===== 結果格納用 ================================================
    FRFR_before_mean = NaN(nRuns,1);
    FRFR_after_mean  = NaN(nRuns,1);
    FRFR_before_std  = NaN(nRuns,1);
    FRFR_after_std   = NaN(nRuns,1);
    delta_FRFR_ns    = NaN(nRuns,1);
    K_ns_per_Vs      = NaN(nRuns,1);
    valid_run        = false(nRuns,1);

    %% ============================================================
    %                  各Runのログから ΔFRFR を算出
    %% ============================================================
    for i = 1:nRuns
        dv = delta_v_list(i);
        Tp = T_pulse_list(i);
        log_file = log_names{i};

        fprintf('\n=== Run %d/%d : ΔV = %.4f V, T_pulse = %.3f s ===\n', ...
                i, nRuns, dv, Tp);
        fprintf('ログ: %s\n', log_file);

        if ~isfile(log_file)
            warning('ログファイルが存在しません: %s', log_file);
            continue;
        end

        L = readtable(log_file);
        vL = L.Properties.VariableNames;

        if ~all(ismember({'time_s','frfr_ns','phase'}, vL))
            warning('time_s / frfr_ns / phase が揃っていないためスキップ: %s', log_file);
            continue;
        end

        t     = L.time_s;
        frfr  = L.frfr_ns;
        phase = L.phase;

        % --- パルス区間 (phase==1) の検出 ---
        mask_pulse = (phase == 1);
        if ~any(mask_pulse)
            warning('phase==1 が存在しないためスキップ: %s', log_file);
            continue;
        end

        t_pulse_start = min(t(mask_pulse));
        t_pulse_end   = max(t(mask_pulse));

        fprintf('  Pulse interval = [%.3f, %.3f] s\n', t_pulse_start, t_pulse_end);

        % --- パルス前後の平均窓 ---
        t_pre_start  = t_pulse_start - pre_margin - pre_window;
        t_pre_end    = t_pulse_start - pre_margin;
        t_post_start = t_pulse_end   + post_margin;
        t_post_end   = t_pulse_end   + post_margin + post_window;

        fprintf('  Pre window  = [%.3f, %.3f] s\n', t_pre_start,  t_pre_end);
        fprintf('  Post window = [%.3f, %.3f] s\n', t_post_start, t_post_end);

        mask_pre  = (t >= t_pre_start)  & (t <  t_pre_end);
        mask_post = (t >= t_post_start) & (t <= t_post_end);

        frfr_pre  = frfr(mask_pre);
        frfr_post = frfr(mask_post);

        if numel(frfr_pre) < 3 || numel(frfr_post) < 3
            warning('前後窓のサンプルが少なすぎるためスキップ: %s', log_file);
            continue;
        end

        % --- 平均・標準偏差と ΔFRFR ---
        FRFR_before_mean(i) = mean(frfr_pre,  'omitnan');
        FRFR_after_mean(i)  = mean(frfr_post, 'omitnan');
        FRFR_before_std(i)  = std(frfr_pre,   'omitnan');
        FRFR_after_std(i)   = std(frfr_post,  'omitnan');

        delta_FRFR_ns(i) = FRFR_after_mean(i) - FRFR_before_mean(i);

        if dv ~= 0 && Tp > 0
            K_ns_per_Vs(i) = delta_FRFR_ns(i) / (dv * Tp);
        end

        fprintf('  FRFR_before = %.3f ns (±%.3f)\n', ...
                FRFR_before_mean(i), FRFR_before_std(i));
        fprintf('  FRFR_after  = %.3f ns (±%.3f)\n', ...
                FRFR_after_mean(i), FRFR_after_std(i));
        fprintf('  ΔFRFR       = %.3f ns\n', delta_FRFR_ns(i));
        fprintf('  K ≈ %.3f ns/(V·s)\n', K_ns_per_Vs(i));

        valid_run(i) = true;
    end

    %% ============================================================
    %                   ΔV vs ΔFRFR の回帰解析
    %% ============================================================
    dv_valid    = delta_v_list(valid_run);
    dfrfr_valid = delta_FRFR_ns(valid_run);
    K_valid     = K_ns_per_Vs(valid_run);

    if numel(dv_valid) < 2
        warning('有効なRunが2未満のため回帰できません。');
        return;
    end

    % --- 一次回帰 ΔFRFR = a*ΔV + b ---
    p = polyfit(dv_valid, dfrfr_valid, 1);
    x_fit = linspace(min(dv_valid), max(dv_valid), 200);
    y_fit = polyval(p, x_fit);

    % --- R^2 ---
    y_pred = polyval(p, dv_valid);
    SS_res = sum((dfrfr_valid - y_pred).^2);
    SS_tot = sum((dfrfr_valid - mean(dfrfr_valid)).^2);
    R2 = 1 - SS_res / SS_tot;

    fprintf('\n=== ΔFRFR vs ΔV 回帰結果 ===\n');
    fprintf('  ΔFRFR ≈ %.4f * ΔV + %.4f  [ns]\n', p(1), p(2));
    fprintf('  R^2 = %.4f\n', R2);

    %% === Plot 1: ΔV vs ΔFRFR（主図） ===============================
    figure('Name','ΔV vs ΔFRFR','NumberTitle','off');
    scatter(dv_valid, dfrfr_valid, 80, 'filled'); hold on;
    plot(x_fit, y_fit, 'r-', 'LineWidth', 2);
    grid on;
    xlabel('\Delta V [V]');
    ylabel('\Delta FRFR [ns]');
    title('\Delta V vs \Delta FRFR');

    % 回帰式と R^2 を2行テキストで表示
    line1 = sprintf('ΔFRFR ≈ %.3f·ΔV + %.3f', p(1), p(2));
    line2 = sprintf('R^2 = %.4f', R2);

    x_text = min(dv_valid) + 0.05*(max(dv_valid)-min(dv_valid));
    y_text = min(dfrfr_valid) + 0.80*(max(dfrfr_valid)-min(dfrfr_valid));
    text(x_text, y_text, {line1, line2}, 'Color','r', 'FontSize',12);

    %% === Plot 2: K vs ΔV（補助図） ================================
    figure('Name','K vs ΔV','NumberTitle','off');
    scatter(dv_valid, K_valid, 80, 'filled');
    grid on;
    xlabel('\Delta V [V]');
    ylabel('K [ns/(V·s)]');
    title('K vs \Delta V');

    %% ============================================================
    %                     解析サマリCSVを書き出し
    %% ============================================================
    analysis_tbl = table( ...
        delta_v_list, ...
        T_pulse_list, ...
        FRFR_before_mean, FRFR_before_std, ...
        FRFR_after_mean,  FRFR_after_std, ...
        delta_FRFR_ns, K_ns_per_Vs, ...
        valid_run, log_names, ...
        'VariableNames', ...
        {'delta_v_V','T_pulse_s', ...
         'FRFR_before_mean_ns','FRFR_before_std_ns', ...
         'FRFR_after_mean_ns','FRFR_after_std_ns', ...
         'delta_FRFR_ns','K_ns_per_Vs', ...
         'valid_run','log_csv_name'} );

    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    out_name  = sprintf('frfr_pulse_sweep_analysis_%s.csv', timestamp);
    writetable(analysis_tbl, out_name);

    fprintf('\n解析サマリを保存しました: %s\n', out_name);
end
