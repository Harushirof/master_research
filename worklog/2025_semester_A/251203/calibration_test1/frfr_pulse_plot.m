%% ==== FRFR vs Time プロット（補助線なし） ====

% 読み込む CSV ファイル名
csv_name = 'frfr_fb_pulse_20251203_193154.csv';

% CSV 読み込み
T = readtable(csv_name);

t     = T.time_s;
frfr  = T.frfr_ns;

%% ---- プロット ----
figure('Name','FRFR vs Time','NumberTitle','off');
plot(t, frfr, 'LineWidth', 1.5);
grid on;

xlabel('Time [s]');
ylabel('FRFR [ns]');
title('FRFR vs Time');

xlim([0 max(t)]);
