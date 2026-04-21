% NIデバイスセッション作成
s = daq('ni');

% 出力チャネル追加
addoutput(s, 'Dev1', 'ao0', 'Voltage');  % 可変出力
addoutput(s, 'Dev1', 'ao1', 'Voltage');  % 常時1.5V固定出力用

% 出力電圧ベクトルを作成（[ao0 ao1] の順）
outputVoltages = [1.54, 1.54];  % ao0=1.5V, ao1=0V
% 1つ目で固定電圧を出し、2つ目で調整

% 電圧を出力
write(s, outputVoltages);
disp("ao0:1.5V, ao1:0.3V を出力開始（10秒間）");

% 10秒待つ
pause(30);

% 出力停止（両チャネルを0Vに）
write(s, [0.0, 0.0]);
disp("出力停止");

