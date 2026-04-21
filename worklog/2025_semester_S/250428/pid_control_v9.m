function pid_control_v8_shortavg()

    % 測定デバイス設定
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch1 = 1;
    slot_ch2 = 2;

    % ★ PIDパラメータ（積極制御）
    Kp = 0.001;    % 比例ゲイン
    Ki = 0.02;     % 積分ゲインアップ！
    Kd = 0;        % 微分なし

    target = 0;  % Δfターゲット
    integral = 0;
    prev_error = 0;

    % ★ 電圧レンジ（0V～3.7V）
    u_min = 0;
    u_max = 3.7;
    u = 0;

    % NIデバイスセッション
    s = daq('ni');
    addoutput(s, 'Dev1', 'ao0', 'Voltage');  % デバイスIDとチャネルを合わせる

    % Δf履歴バッファ
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

            % Δfバッファ更新（最新40点＝約2秒分）
            freq_diff_buffer(end+1) = diff;
            if numel(freq_diff_buffer) > 40
                freq_diff_buffer(1) = [];
            end

            % 直近2秒間のΔf平均
            avg_diff = mean(freq_diff_buffer);

            % PID制御計算
            error = target - avg_diff;
            integral = integral + error * 0.05;  % 積分
            derivative = (error - prev_error) / 0.05;  % 微分（使わない）
            prev_error = error;

            % 制御量計算（比例＋積分）
            u = Kp * error + Ki * integral;
            u = min(max(u, u_min), u_max);  % 0～3.7Vクリップ

            % 制御電圧出力
            write(s, u);

            % プロット更新
            addpoints(hLine, elapsed, diff);
            addpoints(hCtrl, elapsed, u);
            drawnow limitrate;

            pause(0.05);  % 20Hz更新

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end
end
