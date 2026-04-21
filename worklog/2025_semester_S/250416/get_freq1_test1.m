%CH1の周波数をgetする

function freq = get_siglent_freq_main()
    ip = "192.168.1.61";  % オシロのIP
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 30;

    % よりシンプルなコマンドで周波数取得
    writeline(dev, ":MEAS:MAIN:FREQ? CHAN1");
    resp = readline(dev);
    freq = str2double(resp);

    if isnan(freq) || freq == 0
        warning("MEAS:MAIN:FREQ? でも値が取得できませんでした。");
    else
        fprintf("CH1の周波数（MAIN）：%.6f Hz\n", freq);
    end

    clear dev;
end
