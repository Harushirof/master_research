function realtime_ocxo_pi_control_antiwindup_v2
    % === NI DAQ 設定 ===
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % ← デバイス名は環境に応じて変更

    % === 制御パラメータ ===
    Ts = 0.05;                     % サンプリング周期 [s]
    Voffset = 2.5;                 % OCXOの基準制御電圧 [V]
    Vmin = 0; Vmax = 5;            % 出力電圧の上下限 [V]

    % --- PI ゲイン ---
    Kp = 1e-3;                     % 比例ゲイン [V/Hz]
    Ki = 5e-3;                     % 積分ゲイン [V/(Hz·s)]

    % --- 積分項制限（windup防止） ---
    INT_E_LIMIT = 1000;           % 積分誤差の最大値 [Hz·s]

    % === 内部状態 ===
    int_e = 0;                     % 積分誤差
    df_buf = nan(1, round(3 / Ts));  % Δf 平滑用バッファ

    % === オシロスコープ接続 ===
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    % === グラフ描画準備 ===
    figure('Name','改良版PI制御OCXO（Anti-windup）','NumberTitle','off');
    tiledlayout(2,1,'Padding','compact');

    ax1 = nexttile;
    title(ax1, 'Δf [Hz]'); grid on; hold on;
    l_df = animatedline('Color','b');

    ax2 = nexttile;
    title(ax2, 'Vctrl [V]'); grid on; hold on;
    l_v = animatedline('Color','r');

    % === 制御ループ開始 ===
    fprintf("=== PI制御開始（Ctrl+Cで停止） ===\n");
    tic
    while true
        % 1. Δf測定
        df = readDeltaF(dev);
        df_buf = [df_buf(2:end), df];
        df_smooth = mean(df_buf, 'omitnan');

        % 2. 誤差
        e = df_smooth;

        % 3. 仮の積分項更新
        int_e_temp = int_e + e * Ts;
        int_e_temp = min(max(int_e_temp, -INT_E_LIMIT), INT_E_LIMIT);

        % 4. 制御出力（クリッピング前）
        Vctrl_unclipped = Voffset + Kp * e + Ki * int_e_temp;

        % 5. クリッピング
        Vctrl = min(max(Vctrl_unclipped, Vmin), Vmax);

        % 6. windup抑制：飽和していなければ積分項を正式に採用
        if Vctrl == Vctrl_unclipped
            int_e = int_e_temp;
        end

        % 7. 出力
        write(d, Vctrl);

        % 8. グラフ描画
        t = toc;
        addpoints(l_df, t, df_smooth);
        addpoints(l_v,  t, Vctrl);
        drawnow limitrate;

        % 9. ログ表示
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
