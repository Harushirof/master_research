function voltage_freq_response()

    % NIデバイス設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage'); % デバイス名とチャネル適宜変更

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 実験パラメータ
    voltages = 0:0.1:3.5; % 0V〜1Vを0.1Vステップ
    nSamples = 100;      % 各電圧ごとの周波数取得回数
    pause_stabilize = 1; % 電圧変更後の安定化待ち時間

    results = []; % 結果格納用

    fprintf("開始：電圧とCH1周波数の関係性実験\n");

    for v = voltages
        outputSingleScan(s, v);
        pause(pause_stabilize);

        f_values = [];
        for k = 1:nSamples
            writeline(dev, "MEAS:ADV:P1:VAL?");
            resp = readline(dev);
            f1 = str2double(resp);
            if ~isnan(f1)
                f_values(end+1) = f1;
            end
            pause(0.05); % サンプル間隔
        end

        avg_f1 = mean(f_values);
        std_f1 = std(f_values);

        fprintf('V=%.2f V | 平均周波数=%.2f Hz | ボラ=%.2f Hz\n', v, avg_f1, std_f1);

        results = [results; v, avg_f1, std_f1];
    end

    outputSingleScan(s, 0); % 最後に電圧リセット

    % 結果プロット
    figure;
    errorbar(results(:,1), results(:,2), results(:,3), 'o-');
    xlabel('NI出力電圧 [V]');
    ylabel('CH1 周波数 [Hz]');
    title('電圧とCH1周波数の関係');
    grid on;

end
