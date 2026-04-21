function frfr_feedback_variable_gain()

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

    % 周期・目標設定
    period_ns = 100;
    target_frfr = period_ns / 2; % 50ns固定

    % ゲイン設定
    max_Kp = 0.0002;
    min_Kp = 0.00005;
    Ki = 0.000002;

    % 積分制限
    max_integral = 100;
    integral_error = 0;

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1;

    % ログ準備
    filename = sprintf("FRFR_VariableFB_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_ns', 'PhaseError_ns', 'IntegralError', 'Voltage_V', 'Kp_Effective'};
    log_data = [];

    fprintf("FRFRフィードバック制御（ズレ依存ゲイン強化）開始、STOP_FB=1で停止\n");

    start_time = tic;

    while true
        try
            % FRFR取得
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr_ns = frfr_sec * 1e9;

            % 位相誤差補正
            raw_error = frfr_ns - target_frfr;
            error = mod(raw_error + period_ns/2, period_ns) - period_ns/2;

            % ズレ依存ゲイン
            gain_scale = abs(error) / (period_ns/2); % 0〜1
            Kp_effective = min_Kp + (max_Kp - min_Kp) * gain_scale;

            % 積分項更新・制限
            integral_error = integral_error + error * fb_interval;
            integral_error = max(-max_integral, min(max_integral, integral_error));

            % 電圧補正
            delta_v = -Kp_effective * error - Ki * integral_error;
            delta_v = round(delta_v, 4);

            % 電圧更新
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 結果表示
            t = toc(start_time);
            fprintf("t=%.1f s | FRFR=%.2f ns | 誤差=%.2f ns | 電圧=%.4f V | Kp=%.5f\n", ...
                t, frfr_ns, error, voltage, Kp_effective);

            % ログ蓄積
            log_data = [log_data; t, frfr_ns, error, integral_error, voltage, Kp_effective];

            pause(fb_interval);

            % 停止判定
            if evalin('base','exist(''STOP_FB'',''var'')') && evalin('base','STOP_FB') == 1
                fprintf("停止コマンド検知、制御終了します\n");
                break;
            end

        catch ME
            warning("制御中断：%s", ME.message);
            break;
        end
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s);
    clear dev;

    % CSV保存
    writematrix([header; num2cell(log_data)], filename);
    fprintf("\nログを %s に保存しました。\n", filename);
end

