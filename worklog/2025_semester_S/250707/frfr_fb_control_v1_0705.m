function frfr_feedback_control_v1()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 初期電圧
    voltage = 2.94; % 予備実験から安定点
    outputSingleScan(s, voltage);

    % 目標FRFR
    target_frfr = 25; % ns

    % ゲイン設定（微調整推奨）
    Kp = 0.00001; % V/ns単位

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1; % 0.1秒ごとにFB

    fprintf("FRFRフィードバック制御開始（0.1秒間隔, Ctrl+Cで停止）\n");

    while true
        try
            % FRFR測定
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr = str2double(readline(dev));

            % 誤差計算
            error = frfr - target_frfr;

            % 電圧補正計算
            delta_v = -Kp * error;

            % 最小単位考慮（0.001V単位）
            delta_v = round(delta_v, 3);

            % 電圧更新
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 状況表示
            fprintf("FRFR=%.2f ns | 誤差=%.2f ns | 電圧=%.3f V\n", frfr, error, voltage);

            pause(fb_interval);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    outputSingleScan(s, 0); % 電圧リセット
    release(s);
    clear dev;
end
