ip  = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 20;                 % タイムアウト 20 s に拡大
writeline(dev, ":RUN");           % Acquisition 開始

% 1) スロット設定（済みならスキップ）
writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

% 2) 統計 ON（応答を確認）
writeline(dev, ":MEAS:STAT:ENAB ON");
writeline(dev, ":MEAS:STAT:COUN 16");  % まず 16 枚
pause(0.1);                            % 平均が貯まるまで待機

while true
    writeline(dev, ":MEAS:ADV:P1:MEAN?");
    f1 = str2double(readline(dev));    % ← ここでタイムアウトするなら
    writeline(dev, ":MEAS:ADV:P2:MEAN?");
    f2 = str2double(readline(dev));
    fprintf("Δf = %.1f Hz\n", f1 - f2);
    pause(0.1);
end
