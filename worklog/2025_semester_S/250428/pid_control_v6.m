%10秒平均したΔfをターゲットに
function pid_control_v6()

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
    u_min = 0;       % ★ 0Vスタート
    u_max = 3.7;     % ★ 3.7Vリミット
    u = 0;

    % NIセッション（※関数外で作って渡してもOK）
    s = daq('ni');
    addoutput(s, 'Dev1', 'ao0', 'Voltage');

    % 周波数差分バッファ
    freq_diff_buffer = [];

    % プロット
    figure;
    tiledlayout(2,1);
    ax1 = nexttile;
    hLine = animatedline('Parent', ax1);
    title(ax1, 'リアルタイムΔf');
    xlabel(ax1, '時間 (秒)');
    ylabel(ax1, 'Δf [Hz]');
    grid(ax1, 'on');

    ax2 = nexttile;
    hCtrl = animatedline('Parent', ax2, 'Color', 'r');
    title(ax2, '制御電圧 u');
    xlabel(ax2, '時間 (秒)');
    ylabel(ax2, '電圧 [V]');
    grid(ax2, 'on');

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

            % バッファ更新（最新200点まで保存）
            freq_diff_buffer(end+1) = diff;
            if numel(freq_diff_buffer) > 200
                freq_diff_buffer(1) = []; % 古いやつを捨てる
            end

            % 直近10秒間の平均Δfを使う
            avg_diff = mean(freq_diff_buffer);

            % PID制御
            error = target - avg_diff;
            integral = integral + error * 0.05;
            derivative = (error - prev_error) / 0.05;

            u = Kp * error + Ki * integral + Kd * derivative;
            u = min(max(u, u_min), u_max);  % 0～3.7Vにクリップ
            prev_error = error;

            % 電圧出力
            write(s, u);

            % プロット更新
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
