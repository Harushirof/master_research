% 接続
dev = visadev('TCPIP0::192.168.1.61::inst0::INSTR');
configureTerminator(dev, "LF");

% 波形ポイントの時間間隔取得（時間軸用）
writeline(dev, 'WAV:XINCR?');
dx = str2double(readline(dev));

% 連続取得ループ
disp('波形連続取得開始（Ctrl+Cで停止）');
while true
    % CH1取得
    writeline(dev, 'WAV:SOUR CHAN1');
    writeline(dev, 'WAV:DATA?');
    rawData1 = readline(dev);
    y1 = str2num(rawData1); %#ok<ST2NM>

    % CH2取得
    writeline(dev, 'WAV:SOUR CHAN2');
    writeline(dev, 'WAV:DATA?');
    rawData2 = readline(dev);
    y2 = str2num(rawData2); %#ok<ST2NM>

    % 最小サンプル数に合わせる
    n = min(length(y1), length(y2));
    t = (0:n-1) * dx;

    % 必要に応じて、y1, y2, tを保存・処理
    % ここではサンプル数とピーク電圧だけ表示
    fprintf('CH1: %d点, 最大=%.3fV, 最小=%.3fV\n', n, max(y1(1:n)), min(y1(1:n)));
    fprintf('CH2: %d点, 最大=%.3fV, 最小=%.3fV\n', n, max(y2(1:n)), min(y2(1:n)));

    pause(0.1); % 取得間隔（必要なら調整）
end

