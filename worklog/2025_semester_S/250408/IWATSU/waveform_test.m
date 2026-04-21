% --- 接続 ---
s = serialport("COM3", 19200, ...
    "DataBits", 8, "StopBits", 1, ...
    "Parity", "none", "FlowControl", "none");
configureTerminator(s, "LF");
flush(s);
s.Timeout = 5;

% --- 波形形式確認 ---
writeline(s, "DTFORM?");
pause(0.3);
fmt = readline(s);
disp("現在の波形形式:");
disp(fmt);  % → "ASCII" や "BYTE" など

clear s;
