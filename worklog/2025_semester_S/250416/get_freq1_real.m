%リアルタイム周波数獲得に成功

function realtime_freq_display()
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot = 1;  % CH1 の FREQ を割り当てた Advanced Slot 番号（P1）
    disp("リアルタイム周波数表示を開始します（Ctrl+Cで停止）");

    while true
        try
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot));
            resp = readline(dev);
            freq = str2double(resp);

            if isnan(freq) || freq == 0
                fprintf('[%s] 周波数取得失敗\n', datestr(now, 'HH:MM:SS'));
            else
                fprintf('[%s] CH1 FREQ = %.6f Hz\n', datestr(now, 'HH:MM:SS'), freq);
            end

            pause(0.2);  % 200msごとに更新
        catch ME
            warning("エラー発生: %s", ME.message);
            break;
        end
    end

    clear dev;
end
