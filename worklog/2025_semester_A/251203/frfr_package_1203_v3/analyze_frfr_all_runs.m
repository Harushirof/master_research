function analyze_frfr_all_runs(mat_filename)
% 全10回の FRFR 実験ログ (MAT ファイル) から
%  - 「止まった FRFR」の値（平均）のプロット
%  - そのときのボラティリティ（標準偏差）のプロット
%  - 10回分 FRFR 推移の重ね合わせ
% を行う

    %% --- データ読み込み -----------------------------------------------
    S = load(mat_filename);  % run_logs, params が入っている想定

    if isfield(S, 'run_logs')
        run_logs_raw = S.run_logs;
    else
        error('MAT ファイルに run_logs が見つかりません。');
    end

    if isfield(S, 'params')
        params = S.params;
    else
        params = struct();
        warning('params が見つからないため、デフォルト値を使います。');
    end

    % run_logs が cell か struct 配列かを吸収
    if iscell(run_logs_raw)
        get_run = @(i) run_logs_raw{i};
        num_runs = numel(run_logs_raw);
    elseif isstruct(run_logs_raw)
        get_run = @(i) run_logs_raw(i);
        num_runs = numel(run_logs_raw);
    else
        error('run_logs の形式が想定外です。cell か struct 配列を想定しています。');
    end

    %% --- パラメータ設定（なければデフォルト） ------------------------
    if isfield(params, 'total_time')
        total_time = params.total_time;
    else
        total_time = 300;  % [s]
    end

    if isfield(params, 'steady_window_s')
        steady_window_s = params.steady_window_s;
    else
        steady_window_s = 60;  % [s]
    end

    if isfield(params, 'fb_interval')
        fb_interval = params.fb_interval;
    else
        fb_interval = 0.3;  % [s]
    end

    if isfield(params, 'freq_err_threshold')
        freq_th = params.freq_err_threshold;
    else
        freq_th = 0.3;  % [ns/s]
    end

    %% --- 統計量用配列 -------------------------------------------------
    steady_mean = NaN(num_runs,1);  % 「止まった FRFR」の平均値
    steady_std  = NaN(num_runs,1);  % そのときの標準偏差（ボラティリティ）

    %% --- 3つ目の要求：FRFR 推移 10回重ね合わせ ----------------------
    figure('Name','FRFR Overlay (10 runs)','NumberTitle','off');
    hold on; grid on;
    colors = lines(num_runs);

    for r = 1:num_runs
        run_log = get_run(r);

        t        = run_log.time_s;
        frfr     = run_log.frfr_corrected_ns;
        if isfield(run_log, 'freq_err_ns_per_s')
            freq_err = run_log.freq_err_ns_per_s;
        else
            % 古いログ形式なら freq_err を適当に再計算
            drift_ns = run_log.drift_ns;
            freq_err = drift_ns ./ fb_interval;
        end

        % FRFR 推移を描画（重ね合わせ）
        plot(t, frfr, 'Color', colors(r,:), 'DisplayName', sprintf('Run %d', r));

        % --- 「止まったあとの区間」を決める --------------------------
        % total_time の最後 steady_window_s 秒を「止まった区間候補」とする
        steady_start = total_time - steady_window_s;
        mask_steady  = (t >= steady_start) & ~isnan(freq_err) & (abs(freq_err) < freq_th);

        % 閾値を満たすサンプルがない場合は、最後 steady_window_s 秒を無条件採用
        if ~any(mask_steady)
            mask_steady = (t >= steady_start);
        end

        frfr_steady = frfr(mask_steady);

        if ~isempty(frfr_steady)
            steady_mean(r) = mean(frfr_steady);
            steady_std(r)  = std(frfr_steady);
        end
    end

    xlabel('Time [s]');
    ylabel('FRFR corrected [ns]');
    title('FRFR Time Series Overlay (all runs)');
    legend('Location','bestoutside');
    hold off;

    %% --- 1つ目の要求：「止めた FRFR の値」のプロット ----------------
    figure('Name','Steady FRFR (mean)','NumberTitle','off');
    bar(1:num_runs, steady_mean);
    xlabel('Run index');
    ylabel('Steady FRFR mean [ns]');
    title(sprintf('Steady FRFR mean over last %.0f s', steady_window_s));
    grid on;

    %% --- 2つ目の要求：「止まった後のボラティリティ」のプロット ----
    figure('Name','Steady FRFR volatility (std)','NumberTitle','off');
    bar(1:num_runs, steady_std);
    xlabel('Run index');
    ylabel('Steady FRFR std [ns]');
    title(sprintf('Steady FRFR std over last %.0f s', steady_window_s));
    grid on;

    %% --- 結果のテキスト出力 ------------------------------------------
    fprintf('\n=== Steady FRFR stats over last %.0f s (threshold = %.3f ns/s) ===\n', ...
        steady_window_s, freq_th);
    for r = 1:num_runs
        fprintf('Run %2d: FRFR_mean = %+8.3f ns,  FRFR_std = %6.3f ns\n', ...
            r, steady_mean(r), steady_std(r));
    end

    %% --- 統計量を CSV でも保存しておく -------------------------------
    summary_tbl = table( ...
        (1:num_runs).', ...
        steady_mean, ...
        steady_std, ...
        'VariableNames', ...
        {'run_index','steady_mean_frfr_ns','steady_std_frfr_ns'} ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    summary_filename = sprintf('frfr_steady_stats_%s.csv', timestamp);
    writetable(summary_tbl, summary_filename);
    fprintf('\nSteady FRFR 統計を CSV 保存しました: %s\n', summary_filename);
end
