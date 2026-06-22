% bench_p4_all43.m
% パターン4: 追加43機種すべてを種別色で 10MHz 換算重ね描き
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p4_all43
% 出力: bench_p4_all43.png
% 注: 色は種別（OCXO / Rb / Cs / H-maser / GPSDO / MEMS / TCXO）。市販データのみ。

D = benchmark_extra_data();
types = ["OCXO","Rb","Cs","H-maser","GPSDO","MEMS","TCXO"];
cols  = [0.85 0.33 0.10;   % OCXO
         0.00 0.45 0.74;   % Rb
         0.47 0.67 0.19;   % Cs
         0.49 0.18 0.56;   % H-maser
         0.30 0.75 0.93;   % GPSDO
         0.64 0.08 0.18;   % MEMS
         0.50 0.50 0.50];  % TCXO

figure('Name','P4 追加43 (10MHz換算)','NumberTitle','off','Position',[40 40 1120 700]);
hold on;
shown = false(1,numel(types)); legH = []; legL = strings(0,1);
for i = 1:numel(D)
    d = D(i);
    L10 = d.L + 20*log10(10 ./ d.carrier_MHz);
    ti = find(types == string(d.type), 1); if isempty(ti), ti = numel(types); end
    h = plot(d.off, L10, 'o-', 'Color',cols(ti,:), 'LineWidth',0.8, 'MarkerSize',3);
    if ~shown(ti)
        legH(end+1) = h; legL(end+1,1) = types(ti); shown(ti) = true; %#ok<AGROW>
    end
end
set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(legH, legL, 'Location','northeastoutside', 'FontSize',9);
title('パターン4: 追加43機種 (種別色, 10MHz換算)');
exportgraphics(gcf, 'bench_p4_all43.png', 'Resolution',300);
fprintf('保存: bench_p4_all43.png (%d系列)\n', numel(D));
