% COMポート番号に合わせて（ここではCOM3）
s = serialport("COM3", 19200, ...
               "DataBits", 8, ...
               "StopBits", 1, ...
               "Parity", "none", ...
               "FlowControl", "none");

flush(s);  % 念のためバッファを初期化

% *IDN? コマンドで機器識別情報を取得
writeline(s, "*IDN?");
pause(0.2);  % 応答待機（必要なら増やしてOK）
idn = readline(s);

disp("デバイス情報：");
disp(idn);

% 不要になったら接続を解除
clear s;
