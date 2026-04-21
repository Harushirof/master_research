function frfr_feedback_skip_with_min_step()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期設定
    voltage = 0.03;  % 初期電圧は 0V に設定
    outputSingleScan(s, voltage);

    % 制御パラメータ
    Kp = 0.0001;
    fb_interval = 0.3;
    total_time = 20;
    min_voltage = 0;
    max_voltage = 5;

    % 初期FRFR取得（初期ターゲットとして使用）
    writeline(dev, "MEAS:ADV:P3:VAL?");
    frfr_init = str2double(readline(dev)) * 1e9;
    prev_frfr = frfr_init;

    % ログ準備
    filename = sprintf("FRFR_FB_skip_minstep_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_raw_ns', 'FRFR_change_ns', 'Error_ns', 'Voltage_V', 'Delta_V'};
    log_data = [];

    fprintf("最小ステップ・スキップ付きP制御（初期0V, ΔV ≥ 1mV）開始\n");

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
            frfr_raw = str2double(readline(dev)) * 1e9;

            % 差分チェック
            delta_frfr = frfr_raw - prev_frfr;

            if abs(delta_frfr) < 1
                % 1ns未満 → スキップ
                delta_v = 0;
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < 1ns → 電圧維持 (%.3f V)\n", t, delta_frfr, voltage);
            else
                % P制御
                error = frfr_raw - frfr_init;
                delta_v = -Kp * error;

                % 電圧更新（0.001V単位に丸める）
                delta_v = round(delta_v, 3);
                voltage = voltage + delta_v;
                voltage = max(min_voltage, min(max_voltage, voltage));
                outputSingleScan(s, voltage);
                prev_frfr = frfr_raw;

                fprintf("t=%.1f s | FRFR=%.2f ns | 誤差=%.2f ns | ΔV=%.3f | V=%.3f\n", ...
                    t, frfr_raw, error, delta_v, voltage);
            end

            % ログ
            log_data = [log_data; t, frfr_raw, delta_frfr, frfr_raw - frfr_init, voltage, delta_v];
            pause(fb_interval);

        catch ME
            warning("制御中断：%s", ME.message);
            break;
        end
    end

    % 終了
    outputSingleScan(s, 0);
    release(s);
    clear dev;

    % ログ保存
    writecell([header; num2cell(log_data)], filename);
    fprintf("ログを %s に保存しました。\n", filename);
end
