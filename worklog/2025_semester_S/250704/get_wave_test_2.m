%これも変にトリガーかかる、失敗

% visadevオブジェクト作成
dev = visadev('TCPIP0::192.168.1.61::inst0::INSTR');
configureTerminator(dev, "LF");

% データ形式はオシロの既存設定を尊重
% 必要最小限、ソース指定のみ

% CH1波形取得
writeline(dev, 'WAV:SOUR CHAN1');
writeline(dev, 'WAV:DATA?');
rawData1 = readline(dev);
y1 = str2num(rawData1); %#ok<ST2NM>

% CH2波形取得
writeline(dev, 'WAV:SOUR CHAN2');
writeline(dev, 'WAV:DATA?');
rawData2 = readline(dev);
y2 = str2num(rawData2); %#ok<ST2NM>

% 簡易プロット
n = min(length(y1), length(y2));
t = linspace(0, 1, n); % 仮の時間軸（正確な時間取得は別途）
figure;
plot(t, y1(1:n), 'b-', t, y2(1:n), 'r-');
legend('CH1', 'CH2');
xlabel('時間（仮）');
ylabel('電圧 [V]');
title('シンプル波形取得');
