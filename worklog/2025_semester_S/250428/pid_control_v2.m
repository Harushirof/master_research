function realtime_freq_pid_ni()

    % 計測デバイス設定（オシロ or 周波数カウンタ）
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch1 = 1;
    slot_ch2 = 2;

    % PIDパラメータ設定（まずは安全に小さめ）
    Kp = 0.001;
    Ki = 0.01;
    Kd = 0.0001;
    target = 0;  % Δfターゲット
    integral = 0;
    prev_error = 0;
    u_min = -5;   % 出力電圧範囲
    u_max = 5;
    u = 0;  % 初期制御出力

    % NI USB-6211 DAQ設定（Sessionベース）
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % Dev1→自分のデバイス名に合わせる

    % プロット用セットアップ
    figure;
    tiledlayout(2,1);

    ax1 = nexttile;
    hLine = animatedline('Parent', ax1);
    title(ax1, 'リアルタイム周波数差分 Δf');
    xlabel(ax1, '時間 (秒)');
    ylabel(ax1, 'Δf [Hz]');
    grid(ax1, 'on');

    ax2 = nexttile;
    hCtrl = animatedline('Parent', ax2, 'Color', 'r');
    title(ax2, '制御出力 u (電圧)');
    xlabel(ax2, '時間 (秒)');
    ylabel(ax2, '制御電圧 [V]');
    grid(ax2, 'on');

    start_time = tic;

    disp("PID制御開始 (Ctrl+Cで停止)");

    while true
        try
            % 周波数取得（CH1）
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch1));
            freq1 = str2double(readline(dev));

            % 周波数取得（CH2）
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch2));
            freq2 = str2double(readline(dev));

            % Δf計算
            diff = freq1 - freq2;
            elapsed = toc(start_time);

            % PID計算
            error = target - diff;
            integral = integral + error * 0.05;    % 積分成分
            derivative = (error - prev_error) / 0.05; % 微分成分

            u = Kp * error + Ki * integral + Kd * derivative;
            u = min(max(u, u_min), u_max);  % 電圧クリップ
            prev_error = error;

            % 制御電圧を出力
            outputSingleScan(s, u);

            % リアルタイムプロット
            addpoints(hLine, elapsed, diff);
            addpoints(hCtrl, elapsed, u);
            drawnow limitrate;

            pause(0.05);  % 更新間隔20Hz（50ms）

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    % 終了処理（オプション）
    release(s);
    clear s;
end
