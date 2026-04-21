% === IWATSU DS-5312 に接続（オブジェクト作成） ===
s = serialport("COM3", 19200, ...
    "DataBits", 8, "StopBits", 1, ...
    "Parity", "none", "FlowControl", "none");
configureTerminator(s, "LF");
flush(s);
s.Timeout = 5;

% === 現在の波形ソースを問い合わせ ===
writeline(s, "WAVESRC?");
pause(0.3);
src = readline(s);
disp("現在の波形ソース:");
disp(src);  % → CH1, CH2, MATHなど

clear s;  % 通信終了（忘れずに）
