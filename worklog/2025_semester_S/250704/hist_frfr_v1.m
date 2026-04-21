% 対象ファイル名
filename = 'CH1_CH2_FRFR_20250704_161436.csv';

% データ読み込み
data = readmatrix(filename); % 数値部分のみ取得

% FRFRは4列目
frfr_data = data(:, 4);

% NaN除去
frfr_data = frfr_data(~isnan(frfr_data));

% ヒストグラム作成
figure;
histogram(frfr_data, 50, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'black');
xlabel('FRFR 値');
ylabel('出現回数');
title('FRFRのヒストグラム');
grid on;
