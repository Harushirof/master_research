function frfr_fb_experiment()
% FRFR フィードバック制御を複数回実行し、
% 各回のログ取得と統計解析・グラフ描画まで行うメイン関数

    %% --- セッション・デバイス初期化 ----------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 基準用: 固定1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev)); %#ok<NASGU> 

    %% --- 実験パラメータ ------------------------------------------------
    params.num_runs           = 10;        % 実行回数
    params.run_pause_s        = 120;       % [s] 各 run 間のインターバル
    params.fb_interval        = 0.3;       % [s] フィードバック周期 Δt
    params.total_time         = 300;       % [s] 各 run の実行時間
    params.target_frfr_ns     = 50;        % [ns] ログ用（制御には不使用）

    % FRFR の傾き（周波数誤差）に対する P ゲイン
    % freq_err [ns/s] に対して dv [V] を決めるので単位は V / (ns/s)
    params.Kp                 = 0.0001;

    % 周波数誤差がこの閾値より小さければ「ほぼ安定」とみなす
    params.freq_err_threshold = 0.3;       % [ns/s]

    % アンラップ関連
    params.JUMP_DETECT_NS     = 50;        % [ns]
    params.OFFSET_STEP_NS     = 100;       % [ns]

    % AO 設定
    params.ao0_const          = 1.54;      % [V]
    params.ao1_init           = 1.54;      % [V]
    params.min_voltage        = 0.0;       % [V]
    params.max_voltage        = 5.0;       % [V]
    params.min_step           = 0.001;     % [V] 電圧最小ステップ

    % 安定判定（統計用）
    params.steady_window_s    = 60;        % [s] 最後のこの区間で平均・分散をとる
    params.stable_window_s    = 10;        % [s] この長さ連続で閾値内なら「安定到達」と判定

    %% --- 実行 ----------------------------------------------------------
    fprintf("=== FRFR FB 実験開始 ===\n");
    run_logs = struct([]);

    for run_idx = 1:params.num_runs
        fprintf("\n=== Run %d / %d 開始 ===\n", run_idx, params.num_runs);

        % 1 回分の FB 実行
        run_log = run_frfr_fb_single(s, dev, params, run_idx);
        run_logs(run_idx) = run_log; %#ok<AGROW>

        % 次の run までインターバル
        if run_idx < params.num_runs
            fprintf("Run %d 終了。次の Run まで %d 秒待機します...\n", ...
                run_idx, params.run_pause_s);
            pause(params.run_pause_s);
        end
    end

    fprintf("\n=== 全 %d 回の実行が完了。解析を開始します ===\n", params.num_runs);

    % 全 run のログをまとめて解析
    analyze_frfr_runs(run_logs, params);

    fprintf("=== 実験・解析終了 ===\n");
end
