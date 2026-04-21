function frfr_fb_jumpunwrap_v1()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期設定
    voltage = 0.03;
    outputSingleScan(s, voltage);

    % 制御パラメータ
    Kp = 0.0001;                  % 固定ゲイン
    period_ns = 100;
    target_frfr = period_ns / 2; % = 50ns
    jump_threshold = 50;         % ジャンプ閾値 ±50ns
    fb_interval = 0.3;
    total_time = 20;
    min_voltage = 0;
    max_voltage = 5;
    min_step = 0.001;            % 最小変化電圧（1mV）

    % unwrap用変数
    prev_frfr = NaN;
    jump_count = 0;

    % ログ準備
    filename = sprintf("FRFR_JumpUnwrapFB_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_raw_ns', 'FRFR_unwrapped_ns', 'PhaseError_ns', 'Voltage_V'};
    log_data = [];

    fprintf("ジャンプ積算unwrap + ΔFRFRスキップ + 固定Kp 制御開始\n");

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

            % unwrap処理：ジャンプ積算方式
            if isnan(prev_frfr)
                frfr_unwrapped = frfr_ns;
            else
                delta = frfr_ns - prev_frfr;
                if delta > +jump_threshold
                    jump_count = jump_count - 1;  % +方向にジャンプ
                elseif delta < -jump_threshold
                    jump_count = jump_count + 1;  % -方向にジャンプ
                end
                frfr_unwrapped = frfr_ns + 100 * jump_count;
            end

            % ΔFRFRでスキップ判定
            if ~isnan(prev_frfr) && abs(frfr_ns - prev_frfr) < 1
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < 1ns → 電圧維持 (%.3f V)\n", t, frfr_ns - prev_frfr, voltage);
                log_data = [log_data; t, frfr_ns, frfr_unwrapped, NaN, voltage];
                pause(fb_interval);
                continue;
            end

            % 誤差計算（unwrap後 vs 50nsターゲット）
            error = frfr_unwrapped - target_frfr;

            % P制御で電圧更新
            delta_v = -Kp * error;
            delta_v = round(delta_v, 4);

            if abs(delta_v) < min_step
                fprintf("t=%.1f s | ΔV=%.4f < %.4f → 電圧維持 (%.3f V)\n", t, delta_v, min_step, voltage);
            else
                voltage = voltage + delta_v;
                voltage = max(min_voltage, min(max_voltage, voltage));
                outputSingleScan(s, voltage);
                fprintf("t=%.1f s | FRFR=%.2f ns | unwrap=%.2f ns | 誤差=%.2f ns | ΔV=%.4f | V=%.3f\n", ...
                    t, frfr_ns, frfr_unwrapped, error, delta_v, voltage);
            end

            % ログ記録
            log_data = [log_data; t, frfr_ns, frfr_unwrapped, error, voltage];
            prev_frfr = frfr_ns;
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
    fprintf("ログを %s に保存しました。\n", filename);
end
