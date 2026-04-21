% analog_output_0407.m
% NI USB-6211 を使って ao0 から3.0Vを出力するテスト
% 作成日：2025-04-07

% セッションの作成
s = daq.createSession('ni');

% デバイス名が Dev1 の場合（変更が必要な場合あり）
devName = 'Dev1';

% アナログ出力チャンネル ao0 を追加
s.addAnalogOutputChannel(devName, 'ao0', 'Voltage');

% 出力電圧（V）
v_out = 3.0;

% 出力実行
s.outputSingleScan(v_out);

% 結果表示
fprintf('%.2f V を %s の ao0 に出力しました。\n', v_out, devName);
