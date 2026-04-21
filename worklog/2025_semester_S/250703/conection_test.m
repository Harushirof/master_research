%% ① オシロ接続
ip = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 30;

%% ② 接続確認
writeline(dev, "*IDN?");
idn = readline(dev);
fprintf("接続確認 → %s\n", idn);

%% ③ 測定開始コマンド（安定化のため念押し）
writeline(dev, ":STOP"); % 一度停止
pause(0.5);
writeline(dev, ":RUN");  % 測定開始
pause(1);

%% ④ 念のためMEASUREリスト確認（使える項目確認）
writeline(dev, ":MEASure:LIST?");
measList = readline(dev);
fprintf("使用可能なMEASURE項目：%s\n", measList);

%% ⑤ 周波数取得トライ（正式コマンド）
writeline(dev, ":MEASure:ITEM? FREQuency, CHANnel1");
f_ch1 = str2double(readline(dev));

fprintf("CH1の周波数： %.6f Hz\n", f_ch1);

