%電圧が張り付いた、ダメ

function realtime_ocxo_pi_control_plot
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % ← ご自身のデバイス名に変更

    % --- パラメータ ---
    Ts = 0.05;                     % サンプリング周期 [s]
    Voffset = 2.5;                 % OCXOの中間制御電圧
    Vmin = 0; Vmax = 5;            % 電圧出力範囲（0～5V）

    % --- PIゲイン ---
    Kp = 1e-3;                     % 比例ゲイン [V/Hz]
    Ki = 5e-3;                     % 積分ゲイン [V/(Hz·s)]

    % --- 内部状態 ---
    int_e = 0;                     % 積分誤差
    df_buf = nan(1, round(3 / Ts));  % Δf平滑用バッファ

    % --- オシロスコープ接続 ---
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    % --- 描画準備 ---
    figure('Name','PI制御OCXO','NumberTitle','off');
    tiledlayout(2,1,'Padding','compact');

    ax1 = nexttile;
    title(ax1, 'Δf [Hz]'); grid on; hold on;
    l_df = animatedline('Color','b');

    ax2 = nexttile;
    title(ax2, 'Vctrl [V]'); grid on; hold on;
    l_v = animatedline('Color','r');

    % --- 制御ループ開始 ---
    tic
    while true
        % 1. Δf測定（CH1 - CH2）
        df = readDeltaF(dev);
        df_buf = [df_buf(2:end), df];
        df_smooth = mean(df_buf, 'omitnan');

        % 2. 誤差（目標は0Hz）
        e = df_smooth;

        % 3. 積分項
        int_e = int_e + e * Ts;

        % 4. PI制御則
        Vctrl = Voffset + Kp * e + Ki * int_e;

        % 5. 電圧制限（OCXO制御可能範囲）
        Vctrl = min(max(Vctrl, Vmin), Vmax);

        % 6. DAQから制御電圧出力
        write(d, Vctrl);

        % 7. 可視化
        t = toc;
        addpoints(l_df, t, df_smooth);
        addpoints(l_v,  t, Vctrl);
        drawnow limitrate;

        % 8. コンソール出力
        fprintf("t=%.2fs | Δf=%+7.2f Hz | Vctrl=%.3f V\n", t, df_smooth, Vctrl);

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
