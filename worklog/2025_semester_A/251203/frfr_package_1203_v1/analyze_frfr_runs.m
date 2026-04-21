function analyze_frfr_runs(run_logs, params)
% 複数回のログから
% - FRFRがどの位置で止まるか（平均）
% - 止まった位置での分散・標準偏差
% - 安定制御に要した時間
% - FRFR 推移グラフの重ね合わせ
% を計算・表示・CSV 保存する

    num_runs        = numel(run_logs);
    total_time      = params.total_time;
    steady_window_s = params.steady_window_s;
    stable_window_s = params.stable_window_s;
    fb_interval     = params.fb_interval;
    freq_th         = params.freq_err_threshold;

    steady_mean = NaN(num_runs,1);
    steady_std  = NaN(num_runs,1);
    steady_var  = NaN(num_runs,1);
    t_stable    = NaN(num_runs,1);

    figure('Name','FRFR Overlay','NumberTitle','off');
    hold on; grid on;
    colors = lines(num_runs);

    for r = 1:num_runs
        t        = run_logs(r).time_s;
        frfr     = run_logs(r).frfr_corrected_ns;
        freq_err = run_logs(r).freq_err_ns_per_s;

        % --- FRFR 推移グラフ重ね合わせ ---
        plot(t, frfr, 'Color', colors(r,:));

        % --- 「止まったところ」の統計 ---
        steady_start = total_time - steady_window_s;
        mask_steady  = (t >= steady_start) & ~isnan(freq_err) & (abs(freq_err) < freq_th);

        if ~any(mask_steady)
            % 閾値条件を緩め、単に最後の steady_window_s 秒を使う
            mask_steady = (t >= steady_start);
        end

        frfr_steady = frfr(mask_steady);
        if ~isempty(frfr_steady)
            steady_mean(r) = mean(frfr_steady);
            steady_std(r)  = std(frfr_steady);
            steady_var(r)  = var(frfr_steady);
        end

        % --- 安定到達時間の推定 ---
        % 「stable_window_s 秒間連続して |freq_err| < freq_th」であれば安定到達
        n_win = ceil(stable_window_s / fb_interval);
        idx_valid   = find(~isnan(freq_err));
        t_stable_r  = NaN;

        for k = 1:numel(idx_valid)
            idx     = idx_valid(k);
            idx_end = idx + n_win - 1;
            if idx_end > numel(freq_err)
                break;
            end

            if all(abs(freq_err(idx:idx_end)) < freq_th)
                t_stable_r = t(idx);
                break;
            end
        end

        t_stable(r) = t_stable_r;

        if ~isnan(t_stable_r)
            xline(t_stable_r, '--', sprintf('Run %d stable', r), ...
                'Color', colors(r,:), 'LabelVerticalAlignment','bottom');
        end
    end

    xlabel('Time [s]');
    ylabel('FRFR corrected [ns]');
    title('FRFR Time Series Overlay');
    legend(arrayfun(@(r)sprintf('Run %d', r), 1:num_runs, 'UniformOutput', false), ...
        'Location','bestoutside');

    hold off;

    %% --- サマリを表示 ---
    fprintf("\n=== 各 Run の統計結果 ===\n");
    for r = 1:num_runs
        fprintf("Run %2d: FRFR_mean=%.3f ns, std=%.3f ns, var=%.3f, t_stable=%.2f s\n", ...
            r, steady_mean(r), steady_std(r), steady_var(r), t_stable(r));
    end

    %% --- サマリ CSV 保存 ---
    summary_tbl = table( ...
        (1:num_runs).', ...
        steady_mean, ...
        steady_std, ...
        steady_var, ...
        t_stable, ...
        'VariableNames', ...
        {'run_index','steady_mean_frfr_ns','steady_std_frfr_ns','steady_var_frfr','t_stable_s'} ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    summary_filename = sprintf('frfr_summary_%s.csv', timestamp);
    writetable(summary_tbl, summary_filename);
    fprintf("サマリCSVを保存しました: %s\n", summary_filename);
end
