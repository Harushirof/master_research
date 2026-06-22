% bench_p3_ocxo.m
% パターン3: OCXO のみ全部を 10MHz 換算で重ね描き
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p3_ocxo
% 出力: bench_p3_ocxo.png
% 注: 追加分(benchmark_extra_data)の OCXO 11機種を表示。Cybershaft OP21A/OP13 は
%     既存14の cybershaft と同一機種のため、ここでは追加側の値を用いて重複を避ける。

D = benchmark_extra_data();
figure('Name','P3 OCXOのみ (10MHz換算)','NumberTitle','off','Position',[40 40 1500 760]);
hold on;
legL = strings(0,1);
for i = 1:numel(D)
    if string(D(i).type) ~= "OCXO", continue; end
    d = D(i);
    L10 = d.L + 20*log10(10 ./ d.carrier_MHz);
    plot(d.off, L10, 'o-', 'LineWidth',1.0, 'MarkerSize',4);
    legL(end+1,1) = string(d.name); %#ok<AGROW>
end
set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(legL, 'Location','eastoutside', 'Interpreter','none', 'FontSize',8);
title('パターン3: OCXO のみ全部 (10MHz換算)');
drawnow;   % レイアウト確定（凡例の見切れ防止）
exportgraphics(gcf, 'bench_p3_ocxo.png', 'Resolution',300);
fprintf('保存: bench_p3_ocxo.png (OCXO %d機種)\n', numel(legL));
