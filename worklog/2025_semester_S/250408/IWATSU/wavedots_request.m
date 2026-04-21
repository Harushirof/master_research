% === 接続 ===
s = serialport("COM3", 19200, ...
    "DataBits", 8, "StopBits", 1, ...
    "Parity", "none", "FlowControl", "none");
configureTerminator(s, "LF");
flush(s);
s.Timeout = 5;

% === 波形点数を 1000 に設定 ===
writeline(s, "DTPOINTS 1000");
pause(0.3);

% === 設定確認 ===
writeline(s, "DTPOINTS?");
pause(0.3);
points = readline(s);
disp("波形ポイント数（設定後）:");
disp(points);  % → +0001000 になることを期待

clear s;
