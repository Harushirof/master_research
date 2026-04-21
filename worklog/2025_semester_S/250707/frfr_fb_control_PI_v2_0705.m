function frfr_feedback_control_PI_log()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期電圧
    voltage = 2.94;
    outputSingleScan(s, voltage);

    % 目標FRFR
    target_frfr = 25; % [ns]

    % 周期設定（10MHz基準で100ns）
    period_ns = 100;

    % PIゲイン設定
    Kp = 0.0001;
    Ki = 0.000002;

    % 積分制限
    max_integral = 100;

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1; % 制御間隔 [秒]

    % 積分項初期化
    integral_error = 0;

    % ログ保存準備
    filename = sprintf("FRFR_FB_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_ns', 'PhaseError_ns', 'IntegralError', 'Voltage_V'};
    log_data = [];

    fprintf("FRFRフィードバック制御（PI・ログ自動出力）開始：0.1秒間隔, Ctrl+Cで停止\n");

    start_time = tic;

    while true
        try
            % FRFR取得（秒→ナノ秒）
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr_ns = frfr_sec * 1e9;

            % 位相誤差補正
            raw_error = frfr_ns - target_frfr;
            error = mod(raw_error + period_ns/2, period_ns) - period_ns/2;

            % 積分項更新＋制限
            integral_error = integral_error + error * fb_interval;
            integral_error = max(-max_integral, min(max_integral, integral_error));

            % 電圧補正
            delta_v = -Kp * error - Ki * integral_error;
            delta_v = round(delta_v, 4);

            % 電圧更新
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 結果表示
            t = toc(start_time);
            fprintf("t=%.1f s | FRFR=%.2f ns | 誤差=%.2f ns | 積分=%.2f | 電圧=%.4f V\n", ...
                t, frfr_ns, error, integral_error, voltage);

            % ログ蓄積
            log_data = [log_data; t, frfr_ns, error, integral_error, voltage];

            pause(fb_interval);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s);
    clear dev;

    % CSV出力
    writematrix([header; num2cell(log_data)], filename);
    fprintf("\nログを %s に保存しました。\n", filename);
end
