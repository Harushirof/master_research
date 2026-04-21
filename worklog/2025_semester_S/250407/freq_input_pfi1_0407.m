clear all
daqreset

% セッション作成
s = daq.createSession('ni');

% カウンタ入力チャンネル（ctr0）を追加
ch = s.addCounterInputChannel('Dev1', 'ctr0', 'Frequency');

% 使用したいピンに割り当て（例：PFI1 = ピン38）
ch.Terminal = 'PFI1';

% 測定実行（単発）
f = s.inputSingleScan();

fprintf("PFI1（ピン38）から測定された周波数: %.2f Hz\n", f);

