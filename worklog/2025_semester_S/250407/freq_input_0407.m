%%test失敗、NIは出力と入力両方使うときに、最初に指定する必要がある

% freq_input_new_0407.m
% R2024b対応：USB-6211のctr0から周波数を測定（新API使用）

% デバイスとチャンネルを指定
dq = daq("ni");
addinput(dq, "Dev1", "ctr0", "Frequency");

% 周波数レンジ指定（任意）
dq.Channels(1).Range = [1 20e6];  % 1Hz～20MHz など

% 単発で読み取り
f = read(dq, "OutputFormat", "Matrix");

% 表示
fprintf("測定された周波数: %.2f Hz\n", f);
