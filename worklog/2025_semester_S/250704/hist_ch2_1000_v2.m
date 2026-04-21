% ファイル名（必要ならフルパス）
filename = 'CH2_freq_20250704_155157.csv';

% データ読み込み
freq_data = readmatrix(filename);
freq_data = freq_data(~isnan(freq_data));

% 基準値（例：10MHz）からの偏差 [Hz] に変換
ref_freq = 1e7;
delta_f = freq_data - ref_freq;

% ヒストグラム作成
figure;
histogram(delta_f, 100, 'FaceColor', [0.2 0.4 0.8], 'EdgeColor', 'black');
xlabel('基準周波数からの偏差 [Hz]');
ylabel('出現回数');
title('CH2 周波数偏差のヒストグラム');
grid on;

% 平均・中央値ライン表示
hold on;
avg_f = mean(delta_f);
med_f = median(delta_f);
yl = ylim;
plot([avg_f avg_f], yl, 'r-', 'LineWidth', 2, 'DisplayName', '平均');
plot([med_f med_f], yl, 'g-', 'LineWidth', 2, 'DisplayName', '中央値');
legend;
