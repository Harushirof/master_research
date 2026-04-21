% ファイル名（必要ならフルパス指定）
filename = 'CH2_freq_20250704_155157.csv';

% データ読み込み
freq_data = readmatrix(filename);

% NaN除外
freq_data = freq_data(~isnan(freq_data));

% ヒストグラム作成
figure;
histogram(freq_data, 50); % 50ビン、必要なら変更
xlabel('CH2 周波数 [Hz]');
ylabel('出現回数');
title('CH2 周波数のヒストグラム');
grid on;
