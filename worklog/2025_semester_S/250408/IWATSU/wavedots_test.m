% === 接続 ===
s = serialport("COM3", 19200, ...
    "DataBits", 8, "StopBits", 1, ...
    "Parity", "none", "FlowControl", "none");
configureTerminator(s, "LF");
flush(s);
s.Timeout = 5;

% === 波形ポイント数の取得 ===
writeline(s, "DTPOINTS?");
pause(0.3);
points = readline(s);
disp("波形ポイント数:");
disp(points);  % 例: 1000, 500, etc.

clear s;
