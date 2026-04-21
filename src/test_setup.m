%% test_setup.m
% 1から10の数列の2乗をプロットし、results/figures/test_plot.png に保存する

x = 1:10;
y = x.^2;

fig = figure('Visible', 'off');
plot(x, y, '-o', 'LineWidth', 1.5);
xlabel('x');
ylabel('x^2');
title('Square of 1 to 10');
grid on;

saveas(fig, fullfile('results', 'figures', 'test_plot.png'));
close(fig);

fprintf('Saved: results/figures/test_plot.png\n');
