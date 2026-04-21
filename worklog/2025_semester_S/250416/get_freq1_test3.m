function freq = get_freq_gui_assist()
    ip = "192.168.1.61";  % オシロのIPに合わせてね！
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 20;

    slot = 1;  % ← 今回はP1にFREQを設定したので 1
    writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot));
    resp = readline(dev);
    freq = str2double(resp);

    if isnan(freq) || freq == 0
        warning("周波数取得に失敗しました（0 または NaN）");
    else
        fprintf("CH1の周波数（P%d）：%.6f Hz\n", slot, freq);
    end

    clear dev;
end
