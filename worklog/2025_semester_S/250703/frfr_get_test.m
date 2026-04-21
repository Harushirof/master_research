ip = "192.168.1.61";
dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
dev.Timeout = 20; % タイムアウト拡大

% 動作確認（IDN 取得）
writeline(dev, "*IDN?");
idn = readline(dev);
disp("接続確認: " + idn);

% 連続取得
for i = 1:1000
    % FRFR数値取得
    writeline(dev, ":MEAS:ITEM? FRFR, ADVANCED"); % コマンドは仮定、正確な表記要確認
    frfrVal = str2double(readline(dev));

    % 結果表示
    fprintf("FRFR = %.6f\n", frfrVal);

    pause(0.1); % 100msごと
end

