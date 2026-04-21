function frfr_fb_experiment()
% FRFR フィードバック制御を複数回実行し、
% 各回のログを CSV ＋ MAT で保存するメイン関数

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

    %% --- 実行 ----------------------------------------------------------
    fprintf("=== FRFR FB 実験開始 ===\n");

    % 構造体配列ではなく cell にする
    run_logs = cell(params.num_runs, 1);

    for run_idx = 1:params.num_runs
        fprintf("\n=== Run %d / %d 開始 ===\n", run_idx, params.num_runs);

        % 1 回分の FB 実行
        run_log = run_frfr_fb_single(s, dev, params, run_idx);
        run_logs{run_idx} = run_log;

        % 次の run までインターバル
        if run_idx < params.num_runs
            fprintf("Run %d 終了。インターバル中は ao0/ao1 を 0 V にします。\n", run_idx);

            % ★ ここで一旦すべて 0 V に戻す ★
            try
                outputSingleScan(s, [0, 0]);
                fprintf("Run %d: インターバル中 ao0=0.000 V, ao1=0.000 V\n", run_idx);
            catch ME
                warning("Run %d: インターバル中に 0 V 出力へ戻せませんでした: %s", ...
                        run_idx, ME.message);
            end

            fprintf("次の Run まで %d 秒待機します...\n", params.run_pause_s);
            pause(params.run_pause_s);
        end
    end

    fprintf("\n=== 全 %d 回の実行が完了 ===\n", params.num_runs);

    % まとめて MAT ファイルに保存（あとで解析・プロット用）
    timestamp    = datestr(now, 'yyyymmdd_HHMMSS');
    mat_filename = sprintf('frfr_all_runs_%s.mat', timestamp);
    save(mat_filename, 'run_logs', 'params');
    fprintf("全 Run のログを MAT ファイルに保存しました: %s\n", mat_filename);
end
