function freq = get_freq_ch1()
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;

    slot = 1;  % ← GUIでFREQをP1にした前提！
    writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot));
    resp = readline(dev);
    freq = str2double(resp);

    if isnan(freq) || freq == 0
        warning("周波数取得失敗（0 or NaN）");
    else
        fprintf("CH1の周波数（P%d）: %.6f Hz\n", slot, freq);
    end

    clear dev;
end

