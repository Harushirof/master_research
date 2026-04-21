%ch1,2の両方と、その差分をget可能
function realtime_freq_dual()
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch1 = 1;  % CH1のFREQが割り当てられているスロット（例：P1）
    slot_ch2 = 2;  % CH2のFREQが割り当てられているスロット（例：P2）

    disp("CH1 / CH2 の周波数をリアルタイム表示します（Ctrl+Cで停止）");

    while true
        try
            % CH1
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch1));
            resp1 = readline(dev);
            freq1 = str2double(resp1);

            % CH2
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch2));
            resp2 = readline(dev);
            freq2 = str2double(resp2);

            % 差分
            freq_diff = freq1 - freq2;

            % 表示
            fprintf('[%s] CH1: %.6f Hz  |  CH2: %.6f Hz  |  Δf: %.3f Hz\n', ...
                datestr(now, 'HH:MM:SS'), freq1, freq2, freq_diff);

            pause(0.05);  % ← これで20Hz更新（1秒間に約20回）

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    clear dev;
end



