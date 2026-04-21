function realtime_freq_dual_with_std()
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch1 = 1;  % CH1のスロット
    slot_ch2 = 2;  % CH2のスロット

    disp("CH1 / CH2 の周波数差分をリアルタイム表示 + 標準偏差を10秒ごとに描画します");

    % 初期化
    figure;
    tiledlayout(2,1);
    ax1 = nexttile; % 差分リアルタイム描画
    hLine = animatedline('Parent', ax1);
    title(ax1, 'リアルタイム周波数差分 Δf');
    xlabel(ax1, '時間');
    ylabel(ax1, 'Δf [Hz]');

    ax2 = nexttile; % 標準偏差グラフ
    hStd = animatedline('Parent', ax2, 'Color', 'r');
    title(ax2, '10秒ごとの標準偏差');
    xlabel(ax2, '時間');
    ylabel(ax2, '標準偏差 [Hz]');

    freq_diff_buffer = [];
    std_timestamps = [];
    std_values = [];
    start_time = tic;

    while true
        try
            % CH1周波数取得
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch1));
            freq1 = str2double(readline(dev));

            % CH2周波数取得
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch2));
            freq2 = str2double(readline(dev));

            % 差分と時間記録
            diff = freq1 - freq2;
            elapsed = toc(start_time);
            addpoints(hLine, elapsed, diff);
            drawnow limitrate;

            freq_diff_buffer(end+1) = diff;

            % 10秒ごとに標準偏差を計算
            if mod(floor(elapsed), 10) == 0 && (isempty(std_timestamps) || elapsed > std_timestamps(end) + 9.5)
                std_val = std(freq_diff_buffer);
                std_timestamps(end+1) = elapsed;
                std_values(end+1) = std_val;
                addpoints(hStd, elapsed, std_val);
                freq_diff_buffer = []; % バッファをリセット
            end

            pause(0.05);  % 20Hz更新

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end
end
