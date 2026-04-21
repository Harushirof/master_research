function realtime_ocxo_control
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % ← 環境に合わせて変更

    % --- パラメータ設定 ---
    Ts = 0.05;                      % サンプリング周期
    avg_window = 3;                % 平均ウィンドウ（秒）
    buf_len = round(avg_window / Ts);
    Kp = 1e-3;                      % ゲイン (V/Hz)
    Voffset = 2.5;                  % 初期電圧（中央値）
    df_buf = nan(1, buf_len);

    % --- オシロ接続 ---
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    fprintf("=== OCXO 周波数制御 開始 ===\n");

    % --- 制御ループ ---
    while true
        % Δf読み取り
        df = readDeltaF(dev);
        df_buf = [df_buf(2:end), df];

        % 移動平均（NaN除外）
        df_mean = mean(df_buf, 'omitnan');

        % 出力電圧を計算（飽和あり）
        Vctrl = Voffset + Kp * df_mean;
        Vctrl = min(max(Vctrl, 0), 5);  % 0V〜5V に制限

        % NI DAQ に出力
        write(d, Vctrl);

        % 表示
        fprintf("Δf = %+7.2f Hz, Vctrl = %.3f V\n", df_mean, Vctrl);

        pause(Ts);
    end
end

function df = readDeltaF(dev)
    writeline(dev, ":MEAS:ADV:P1:VAL?");
    f1 = str2double(readline(dev));
    writeline(dev, ":MEAS:ADV:P2:VAL?");
    f2 = str2double(readline(dev));
    df = f1 - f2;
end

