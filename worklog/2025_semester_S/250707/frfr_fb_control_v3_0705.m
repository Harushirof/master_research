function frfr_feedback_control_phaseaware()

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

    % 周期設定（OCXO 10MHzなら周期100ns）
    period_ns = 100;

    % ゲイン設定（V/ns単位）
    %Kp = 0.00001;小さすぎて電圧動かず
    Kp = 0.0001;
    %Kp = 0.001;
    %Kp = 0.01;

    % 制御パラメータ
    min_voltage = 0;
    max_voltage = 5;
    fb_interval = 0.1; % 0.1秒ごと制御

    fprintf("FRFR位相補正付きフィードバック開始（0.1秒間隔, Ctrl+Cで停止）\n");

    while true
        try
            % FRFR取得（秒単位 → ナノ秒）
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr_ns = frfr_sec * 1e9;

            % 位相差補正誤差計算
            raw_error = frfr_ns - target_frfr;
            error = mod(raw_error + period_ns/2, period_ns) - period_ns/2;

            % 電圧補正
            delta_v = -Kp * error;
            delta_v = round(delta_v, 3); % 0.001V単位

            % 電圧更新
            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 状況表示
            fprintf("FRFR=%.2f ns | 位相誤差=%.2f ns | 電圧=%.3f V\n", frfr_ns, error, voltage);

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
