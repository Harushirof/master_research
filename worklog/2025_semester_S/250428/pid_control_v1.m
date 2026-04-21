function realtime_freq_pid_ni()
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch1 = 1;
    slot_ch2 = 2;

    % PIDパラメータ
    Kp = 0.001;
    Ki = 0.01;
    Kd = 0.0001;
    target = 0;
    integral = 0;
    prev_error = 0;
    u_min = -5;
    u_max = 5;
    u = 0;

    % NI USB-6211 DAQ設定
    daq_session = daq('ni');
    addoutput(daq_session, 'Dev1', 'ao0', 'Voltage');  % Dev1→自分のデバイス名に合わせて

    % プロット準備
    figure;
    tiledlayout(2,1);
    ax1 = nexttile;
    hLine = animatedline('Parent', ax1);
    title(ax1, 'リアルタイム周波数差分 Δf');
    xlabel(ax1, '時間');
    ylabel(ax1, 'Δf [Hz]');

    ax2 = nexttile;
    hCtrl = animatedline('Parent', ax2, 'Color', 'r');
    title(ax2, '制御出力 u');
    xlabel(ax2, '時間');
    ylabel(ax2, '制御電圧 [V]');

    start_time = tic;
    disp("PID制御開始 (Ctrl+Cで停止)");

    while true
        try
            % 周波数取得
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch1));
            freq1 = str2double(readline(dev));

            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch2));
            freq2 = str2double(readline(dev));

            diff = freq1 - freq2;
            elapsed = toc(start_time);

            % PID計算
            error = target - diff;
            integral = integral + error * 0.05;
            derivative = (error - prev_error) / 0.05;
            u = Kp * error + Ki * integral + Kd * derivative;
            u = min(max(u, u_min), u_max);
            prev_error = error;

            % NI USB-6211に電圧出力
            write(daq_session, u);

            % プロット
            addpoints(hLine, elapsed, diff);
            addpoints(hCtrl, elapsed, u);
            drawnow limitrate;

            pause(0.05);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end
end
