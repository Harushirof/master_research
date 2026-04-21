%PI制御

function frfr_feedback_variable_gain_unwrap_20s()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期設定
    voltage = 2.94;
    outputSingleScan(s, voltage);

    period_ns = 100;
    target_frfr = period_ns / 2;  % 50ns固定ターゲット

    % ゲイン設定
    max_Kp = 0.00008;
    min_Kp = 0.00001;
    Ki = 0.0000002;

    % 積分制限
    max_integral = 100;
    integral_error = 0;

    % FBパラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.2;
    total_time = 60;  % 60秒実行

    % ログ準備
    filename = sprintf("FRFR_UnwrapFB_20s_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_raw_ns', 'FRFR_unwrapped_ns', 'PhaseError_ns', 'IntegralError', 'Voltage_V', 'Kp_Effective'};
    log_data = [];

    fprintf("FRFRフィードバック制御（unwrap適用, 20秒）開始\n");

    % unwrap用変数
    prev_frfr = NaN;
    unwrapped_frfr = NaN;

    start_time = tic;

    while true
        t = toc(start_time);
        if t > total_time
            fprintf("20秒経過、制御終了します\n");
            break;
        end

        try
            % FRFR取得
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr_ns = frfr_sec * 1e9;

            % unwrap処理
            if isnan(prev_frfr)
                unwrapped_frfr = frfr_ns;
            else
                delta = frfr_ns - prev_frfr;
                if delta > +50
                    unwrapped_frfr = unwrapped_frfr + (delta - 100);
                elseif delta < -50
                    unwrapped_frfr = unwrapped_frfr + (delta + 100);
                else
                    unwrapped_frfr = unwrapped_frfr + delta;
                end
            end
            prev_frfr = frfr_ns;

            % 誤差計算（unwrap後）
            raw_error = unwrapped_frfr - target_frfr;
            error = mod(raw_error + period_ns/2, period_ns) - period_ns/2;

            % ゲインスケーリング
            gain_scale = abs(error) / (period_ns/2);
            Kp_effective = min_Kp + (max_Kp - min_Kp) * gain_scale;

            % 積分項更新
            integral_error = integral_error + error * fb_interval;
            integral_error = max(-max_integral, min(max_integral, integral_error));

            % 電圧更新
            delta_v = -Kp_effective * error - Ki * integral_error;
            delta_v = round(delta_v, 4);
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 表示
            fprintf("t=%.1f s | FRFR=%.2f ns | unwrap=%.2f ns | 誤差=%.2f ns | 電圧=%.4f V | Kp=%.5f\n", ...
                t, frfr_ns, unwrapped_frfr, error, voltage, Kp_effective);

            % ログ記録
            log_data = [log_data; t, frfr_ns, unwrapped_frfr, error, integral_error, voltage, Kp_effective];
            pause(fb_interval);

        catch ME
            warning("制御中断：%s", ME.message);
            break;
        end
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s);
    clear dev;

    % 保存
    writecell([header; num2cell(log_data)], filename);
    fprintf("\nログを %s に保存しました。\n", filename);
end
