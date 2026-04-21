function frfr_feedback_control_v2()

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

    % ゲイン設定（単位：V/ns）
    Kp = 0.00001;

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1; % 0.1秒ごと制御

    fprintf("FRFRフィードバック制御開始（0.1秒間隔, Ctrl+Cで停止）\n");

    while true
        try
            % FRFR測定（秒単位返却 → ナノ秒へ変換）
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr_ns = frfr_sec * 1e9;

            % 誤差計算
            error = frfr_ns - target_frfr;

            % 電圧補正計算
            delta_v = -Kp * error;
            delta_v = round(delta_v, 3); % 0.001V単位

            % 電圧更新
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 状況表示
            fprintf("FRFR=%.2f ns | 誤差=%.2f ns | 電圧=%.3f V\n", frfr_ns, error, voltage);

            pause(fb_interval);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    outputSingleScan(s, 0);
    release(s);
    clear dev;
end
