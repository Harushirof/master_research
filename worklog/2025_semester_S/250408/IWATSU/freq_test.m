% === 接続初期化 ===
s = serialport("COM3", 19200, ...
    "DataBits", 8, ...
    "StopBits", 1, ...
    "Parity", "none", ...
    "FlowControl", "none");
configureTerminator(s, "LF");
s.Timeout = 10;
flush(s);

% === 波形取得前の設定（冗長に再指定） ===
writeline(s, "WAVESRC CH1");
pause(0.1);
writeline(s, "DTFORM ASCII");
pause(0.1);
writeline(s, "DTPOINTS 500");
pause(0.2);

% === 波形取得コマンド ===
writeline(s, "DTWAVE?");
pause(1.0);  % 応答を待つ

% === データ受信 ===
n = s.NumBytesAvailable;
raw = read(s, n, "char");
clear s;

% === データ整形 ===
data = str2double(strsplit(raw, ','));
data = data(~isnan(data));

% === 波形の中央化（DC成分除去） ===
data_centered = data - mean(data);

% === ゼロ交差検出（正→負） ===
signs = sign(data_centered);
crossings = find(diff(signs) < 0);  % 正→負

if length(crossings) >= 2
    Ts = 1e-9;  % 1ns間隔（※後で正確に調整）
    periods = diff(crossings) * Ts * 2;
    mean_period = mean(periods);
    freq = 1 / mean_period;
    fprintf("推定周波数：%.3f Hz\n", freq);
else
    disp("ゼロ交差点が2つ未満（解析不可）");
end

% === 波形表示（確認用） ===
plot(data);
title("取得波形（500点）");
xlabel("サンプル番号");
ylabel("電圧");
grid on;
