% 再接続
ip = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 30;

% 念のためIDN確認
writeline(dev, "*IDN?");
disp(readline(dev));

% 測定開始
writeline(dev, ":RUN");
pause(1);

% 周波数取得（前回動いていた形式）
writeline(dev, ":MEASure:ITEM? FREQ, C1");
f_ch1 = str2double(readline(dev));
fprintf("CH1の周波数：%.6f Hz\n", f_ch1);
