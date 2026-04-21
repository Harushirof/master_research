% sweep_output_0407.m
% 電圧を0Vから5Vまで連続的にスイープ出力する
% 作成日：2025-04-07

% セッション作成
s = daq.createSession('ni');

% デバイス名（必要に応じて変更）
devName = 'Dev1';

% アナログ出力チャンネル ao0 を追加
s.addAnalogOutputChannel(devName, 'ao0', 'Voltage');

% スイープのパラメータ設定
startV = 0.0;     % 初期電圧
endV   = 3.0;     % 最終電圧
steps  = 100;     % ステップ数
pauseT = 0.5;    % 各ステップ間の時間（秒）

% スイープ電圧を生成
voltages = linspace(startV, endV, steps);

% スイープ開始
disp('スイープ出力開始...');
for v = voltages
    s.outputSingleScan(v);
    pause(pauseT);
end
disp('スイープ完了。');
