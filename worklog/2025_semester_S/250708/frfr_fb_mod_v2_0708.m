%P制御
%ゲインは固定

function frfr_feedback_simpleP_unwrap()

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

    % 制御パラメータ
    Kp = 0.0001;                  % 固定ゲイン
    period_ns = 100;              % FRFRの周期
    fb_interval = 0.1;            % 0.1秒ごとに制御
    total_time = 20;              % 20秒で停止
    min_voltage = 0;
    max_voltage = 5;

    % unwrap変数
    prev_frfr = NaN;
    unwrapped_frfr = NaN;
    frfr_init = NaN;

    % ログ準備
    filename = sprintf("FRFR_SimplePFB_20s_log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time_s', 'FRFR_raw_ns', 'FRFR_unwrapped_ns', 'PhaseError_ns', 'Voltage_V'};
    log_data = [];

    fprintf("簡易FRFR P制御（unwrap + 初期原点 + 固定Kp）開始\n");

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
                frfr_init = frfr_ns;  % 初期基準（≒50ns）保存
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

            % 初期値に合わせた誤差計算
            error = unwrapped_frfr - frfr_init;

            % P制御で電圧補正
            delta_v = -Kp * error;
            delta_v = round(delta_v, 4);
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 表示
            fprintf("t=%.1f s | FRFR=%.2f ns | unwrap=%.2f ns | 誤差=%.2f ns | V=%.4f\n", ...
                t, frfr_ns, unwrapped_frfr, error, voltage);

            % ログ保存
            log_data = [log_data; t, frfr_ns, unwrapped_frfr, error, voltage];
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

    % CSV保存
    writecell([header; num2cell(log_data)], filename);
    fprintf("ログを %s に保存しました。\n", filename);
end
