function frfr_feedback_control_PI_stop()

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

    % 周期・目標設定（10MHz想定）
    period_ns = 100;
    target_frfr = period_ns / 2; % 50nsを目標

    % PIゲイン
    Kp = 0.0001;
    Ki = 0.000002;

    % 積分制限
    max_integral = 100;

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1;

    % 積分項初期化
    integral_error = 0;

    % ログ保存準備
    filename = sprintf("FRFR_FB_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_ns', 'PhaseError_ns', 'IntegralError', 'Voltage_V'};
    log_data = [];

    fprintf("FRFRフィードバック制御（目標50ns・Ctrl+C対応）開始：停止コマンドで終了、ログ自動保存\n");

    start_time = tic;

    % 停止用フラグ
    stop_flag = false;

    % 停止コマンド受付用並列タスク
    stop_listener = parfeval(@listen_stop_command, 0);

    try
        while true
            % FRFR取得
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

            % 停止コマンド判定
            if evalin('base','exist(''STOP_FB'',''var'')') && evalin('base','STOP_FB') == 1
                fprintf("停止コマンド検知、制御終了します\n");
                break;
            end
        end

    catch ME
        warning("制御中断：%s", ME.message);
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s);
    clear dev;

    % CSV保存
    writematrix([header; num2cell(log_data)], filename);
    fprintf("\nログを %s に保存しました。\n", filename);

    % 停止フラグ解除
    cancel(stop_listener);
end
