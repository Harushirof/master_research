ip  = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 10;

% 1) 測定スロットを周波数に設定しておく（手動 or SCPI）
writeline(dev, ":MEASure:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev, ":MEASure:ADV:P2:TYPE FREQuency,CHAN2");

% 2) 統計を有効にして平均個数を増やす
writeline(dev, ":MEASure:STATistic:ENABle ON");
writeline(dev, ":MEASure:STATistic:COUNt 64");   % 64 波形ぶん平均
pause(0.2);                                     % 初期集計待ち

disp("平均化した周波数差を表示（Ctrl+C で停止）");
while true
    % CH1/CH2 の平均値(Hz)を取得
    writeline(dev, ":MEASure:ADV:P1:MEAN?");
    f1 = str2double(readline(dev));
    writeline(dev, ":MEASure:ADV:P2:MEAN?");
    f2 = str2double(readline(dev));

    dF = f1 - f2;
    fprintf('[%s]  CH1 %.6f  |  CH2 %.6f  |  Δf %.3f Hz\n', ...
            datestr(now,'HH:MM:SS.FFF'), f1, f2, dF);

    pause(0.2);   % 表示 5 Hz（制御ループならもっと遅くて OK）
end
