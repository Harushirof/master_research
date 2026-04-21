function frfr_get_test1()

    % オシロ接続設定
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 単発でFRFR取得
    writeline(dev, "MEAS:ADV:P3:VAL?");
    resp = readline(dev);
    frfr_sec = str2double(resp); % 秒単位

    % ナノ秒単位へ変換
    frfr_ns = frfr_sec * 1e9;

    % 結果表示
    fprintf("取得文字列: %s\n", resp);
    fprintf("FRFR値 [ns]: %.3f\n", frfr_ns);

    clear dev;
end
