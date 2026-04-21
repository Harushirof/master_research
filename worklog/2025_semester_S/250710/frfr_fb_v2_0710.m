function frfr_fb_unwrap_minimal_v1()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続（SIGLENTなど）
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期設定
    voltage = 0.03;  % 初期電圧
    outputSingleScan(s, voltage);

    Kp = 0.0001;      % 固定ゲイン
    fb_interval = 0.5;
    total_time = 20;
    min_voltage = 0;
    max_voltage = 5;

    prev_unwrap = NaN;
    prev_frfr = NaN;
    unwrapped = NaN;

    % ログ準備
    header = {'Time_s','FRFR_raw_ns','FRFR_unwrap_ns','DeltaFRFR','Error_ns','DeltaV','Voltage'};
    log_data = [];

    fprintf("unwrap処理付き・ΔFRFR<1nsでスキップ・初期0.03V・Kp固定制御開始\n");
    t0 = tic;

    while true
        t = toc(t0);
        if t > total_time
            fprintf("20秒経過、終了します\n");
            break;
        end

        try
            % FRFR取得
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_ns = str2double(readline(dev)) * 1e9;

            % unwrap処理
            if isnan(prev_frfr)
                unwrapped = frfr_ns;
            else
                delta = frfr_ns - prev_frfr;
                if delta > 50
                    unwrapped = unwrapped + (delta - 100);
                elseif delta < -50
                    unwrapped = unwrapped + (delta + 100);
                else
                    unwrapped = unwrapped + delta;
                end
            end

            % ΔFRFRでスキップ判定
            delta_frfr = unwrapped - prev_unwrap;
            if ~isnan(prev_unwrap) && abs(delta_frfr) < 1
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < 1ns → 電圧維持 (%.3f V)\n", t, delta_frfr, voltage);
                log_data = [log_data; t, frfr_ns, unwrapped, delta_frfr, NaN, 0, voltage];
                pause(fb_interval);
                prev_frfr = frfr_ns;
                continue;
            end

            % 誤差と電圧補正
            error = unwrapped - 50;  % 50ns目標
            delta_v = -Kp * error;
            delta_v = round(delta_v, 4);

            % 電圧更新（最小0.001V単位）
            if abs(delta_v) < 0.001
                delta_v = sign(delta_v) * 0.001;
            end

            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            fprintf("t=%.1f s | FRFR=%.2f ns | unwrap=%.2f ns | 誤差=%.2f ns | ΔV=%.3f | V=%.3f\n", ...
                t, frfr_ns, unwrapped, error, delta_v, voltage);

            log_data = [log_data; t, frfr_ns, unwrapped, delta_frfr, error, delta_v, voltage];

            prev_unwrap = unwrapped;
            prev_frfr = frfr_ns;

            pause(fb_interval);

        catch ME
            warning("中断: %s", ME.message);
            break;
        end
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s); clear dev;

    % ログ保存
    fname = sprintf("FRFR_FB_UnwrapMinimal_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    writecell([header; num2cell(log_data)], fname);
    fprintf("ログを %s に保存しました。\n", fname);
end
