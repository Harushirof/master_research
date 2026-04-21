% 2つのOCXOの「周波数差=0（ドリフト無し）」を目指したFB版 + CSVログ保存版
function frfr_fb_1202_v2()

    %% --- 初期設定 -------------------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev));

    %% --- パラメータ -----------------------------------------------------
    fb_interval = 0.3;              % [s] フィードバック周期
    total_time  = 180;              % [s] 実行時間

    % 目標FRFRは制御には使わない（ログ用）
    target      = 50;               % [ns]

    Kp          = 0.0001;           % 比例ゲイン（ドリフトP制御）

    drift_threshold = 0.1;          % [ns] ドリフトがこの値より小さければ保持

    JUMP_DETECT_NS = 50;            % [ns] ラップ検出閾値
    OFFSET_STEP_NS = 100;           % [ns] オフセット累積

    ao0_const   = 1.54;             % [V]
    v_ao1       = 1.54;             % [V]
    min_voltage = 0.0;
    max_voltage = 5.0;
    min_step    = 0.001;            % [V]

    stable_duration        = 10;    % [s]
    stable_delta_threshold = 0.5;   % [ns]

    %% --- 状態変数 ------------------------------------------------------
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_corrected = NaN;
    last_stable_time    = NaN;

    %% --- ログ -----------------------------------------------------------
    time_log  = [];
    frfr_log  = [];
    ao1_log   = [];
    drift_log = [];
    delta_raw_log = [];
    dv_log    = [];

    %% --- グラフ ---------------------------------------------------------
    figure('Name','FRFR Feedback Monitor','NumberTitle','off');
    tiledlayout(2,1,'TileSpacing','compact');

    ax1 = nexttile(1);
    h_frfr = plot(ax1, NaN, NaN, 'r-'); grid on;
    ylabel(ax1,'Corrected FRFR [ns]');
    title(ax1,'Corrected FRFR Over Time');

    ax2 = nexttile(2);
    h_ao1 = plot(ax2, NaN, NaN, 'b-'); grid on;
    ylabel(ax2,'Voltage on ao1 [V]');
    xlabel(ax2,'Time [s]');
    title(ax2,'ao1 Voltage (FB Channel) Over Time');

    linkaxes([ax1, ax2], 'x');

    %% --- 初期出力 ------------------------------------------------------
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("開始: ao0=%.3f V (固定), ao1=%.3f V (初期)\n", ao0_const, v_ao1);

    %% --- 計測開始 ------------------------------------------------------
    t_start = datetime('now');
    stable_buffer = [];

    %% --- メインループ --------------------------------------------------
    while true
        t = seconds(datetime('now') - t_start);
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            %% --- 測定 ---------------------------------------------------
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            raw_frfr = frfr_sec * 1e9; % [ns]

            %% --- FRFR補正（アンラップ） -------------------------------
            if isnan(prev_raw_frfr)
                delta_raw = NaN;
            else
                delta_raw = raw_frfr - prev_raw_frfr;

                if delta_raw <= -JUMP_DETECT_NS
                    frfr_offset = frfr_offset + OFFSET_STEP_NS;
                    fprintf("ラップダウン: Δ=%.1f → offset=%.1f\n", delta_raw, frfr_offset);

                elseif delta_raw >= +JUMP_DETECT_NS
                    frfr_offset = frfr_offset - OFFSET_STEP_NS;
                    fprintf("ラップアップ:  Δ=%.1f → offset=%.1f\n", delta_raw, frfr_offset);
                end
            end

            frfr_corrected = raw_frfr + frfr_offset;
            prev_raw_frfr  = raw_frfr;

            %% --- 安定判定（表示用） -----------------------------------
            if ~isnan(delta_raw)
                stable_buffer = [stable_buffer, abs(delta_raw)];
                if numel(stable_buffer) > round(stable_duration / fb_interval)
                    stable_buffer(1) = [];
                end
            end

            %% --- ドリフト計算 ------------------------------------------
            if isnan(prev_frfr_corrected)
                drift_ns = NaN;
            else
                drift_ns = frfr_corrected - prev_frfr_corrected;
            end
            prev_frfr_corrected = frfr_corrected;

            %% --- FB制御（ドリフトP制御） -----------------------------
            dv = 0;  % ログのため毎回初期化

            if isnan(drift_ns) || abs(drift_ns) < drift_threshold
                % --- drift が小さい：制御しない ---
                fprintf("t=%.1f s | FRFRcorr=%.2f ns | drift=%.3f ns < %.2f → ao1維持\n", ...
                        t, frfr_corrected, drift_ns, drift_threshold);

            else
                % --- drift が大きい：制御 ---
                dv = -Kp * drift_ns;
                dv = round(dv, 4);

                if abs(dv) < min_step
                    dv = min_step * sign(-drift_ns);
                end

                v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);

                fprintf("t=%.1f s | FRFRcorr=%.2f | drift=%.3f ns | ΔV=%.4f | ao1=%.4f V\n", ...
                        t, frfr_corrected, drift_ns, dv, v_ao1);
            end

            %% --- ログ --------------------------------------------------
            time_log(end+1)      = t;
            frfr_log(end+1)      = frfr_corrected;
            ao1_log(end+1)       = v_ao1;
            drift_log(end+1)     = drift_ns;
            delta_raw_log(end+1) = delta_raw;
            dv_log(end+1)        = dv;

            %% --- グラフ更新 --------------------------------------------
            set(h_frfr, 'XData', time_log, 'YData', frfr_log);
            set(h_ao1,  'XData', time_log, 'YData', ao1_log);

            if t > 30
                xlim(ax1, [t-30, t+1]);
                xlim(ax2, [t-30, t+1]);
            else
                xlim(ax1, [0, max(30, t+1)]);
                xlim(ax2, [0, max(30, t+1)]);
            end

            drawnow limitrate;
            pause(fb_interval);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    %% --- CSV 保存 ------------------------------------------------------
    time_vec  = time_log(:);
    frfr_vec  = frfr_log(:);
    ao1_vec   = ao1_log(:);
    drift_vec = drift_log(:);
    delt_vec  = delta_raw_log(:);
    dv_vec    = dv_log(:);

    log_tbl = table(...
        time_vec, ...
        frfr_vec, ...
        ao1_vec, ...
        drift_vec, ...
        delt_vec, ...
        dv_vec, ...
        'VariableNames', ...
        {'time_s','frfr_corrected_ns','ao1_V','drift_ns','delta_raw_ns','dv_V'} ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    filename  = ['frfr_log_' timestamp '.csv'];

    writetable(log_tbl, filename);
    fprintf("CSVログを保存しました: %s\n", filename);

    %% --- 終了処理 ------------------------------------------------------
    outputSingleScan(s, [0, 0]);
end


function cleanupDAQ(s, dev)
    try, stop(s);    end
    try, release(s); end
    try, clear dev;  end
end
