function realtime_ocxo_control_plot
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % ← デバイス名を変更してください

    % --- パラメータ設定 ---
    Ts = 0.05;                       % サンプリング周期（秒）
    avg_window = 3;                 % 移動平均ウィンドウ（秒）
    buf_len = round(avg_window / Ts);
    Kp = 1e-3;                       % ゲイン (V/Hz)
    Voffset = 2.5;                   % 制御基準電圧
    df_buf = nan(1, buf_len);

    % --- オシロ接続 ---
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    fprintf("=== OCXO フィードバック制御 開始 ===\n");

    % --- 描画セットアップ ---
    figure('Name','Δf & Vctrl','NumberTitle','off');
    tiledlayout(2,1,'Padding','compact');

    ax1 = nexttile;
    title(ax1,'周波数差 Δf [Hz]');
    grid(ax1, 'on'); hold(ax1, 'on');
    l_df = animatedline(ax1, 'Color', 'b');

    ax2 = nexttile;
    title(ax2,'制御電圧 V_{ctrl} [V]');
    grid(ax2, 'on'); hold(ax2, 'on');
    l_v  = animatedline(ax2, 'Color', 'r');

    % --- 制御ループ ---
    tic
    while true
        % Δf読み取り
        df = readDeltaF(dev);
        df_buf = [df_buf(2:end), df];

        % Δfの移動平均
        df_mean = mean(df_buf, 'omitnan');

        % 制御電圧計算
        Vctrl = Voffset + Kp * df_mean;
        Vctrl = min(max(Vctrl, 0), 5);  % 制限（0〜5V）

        % DAQ に出力
        write(d, Vctrl);

        % 時刻取得・プロット
        t = toc;
        addpoints(l_df, t, df_mean);
        addpoints(l_v,  t, Vctrl);
        drawnow limitrate;

        % 表示
        fprintf("t=%.2fs | Δf=%+7.2f Hz | Vctrl=%.3f V\n", t, df_mean, Vctrl);

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

