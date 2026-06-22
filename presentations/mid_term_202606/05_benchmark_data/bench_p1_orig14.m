% bench_p1_orig14.m
% パターン1: 既存14機種（dBCperHz.xlsx）を 10MHz 換算で重ね描き
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p1_orig14
% 出力: bench_p1_orig14.png
% 注: 市販データのみ。本研究データを重ねる場合は overlay_benchmark_10MHz.m を使用。

xlsx = "dBCperHz.xlsx";
devs = ["Ceyear2G","Ceyear3G","DST2","DST1","SPXONo1","OEO","Abracon-U", ...
        "EPSON-VCSO","TCXO-CMOS","iMaser-10MLN","PRS10","DST-24.576", ...
        "cybershaft(638000円)","cybershaft(121,000円)"];

figure('Name','P1 既存14 (10MHz換算)','NumberTitle','off','Position',[40 40 1500 760]);
hold on;
for i = 1:numel(devs)
    d = devs(i);
    N = cell2mat(readcell(xlsx,"Sheet",d,"Range","A3:A3"));
    f = cell2mat(readcell(xlsx,"Sheet",d,"Range","A2:A2"));            % 搬送波 [GHz]
    C = cell2mat(readcell(xlsx,"Sheet",d,"Range",strcat("A4:B",num2str(3+N))));
    L10 = C(:,2) + 20*log10(0.01 ./ f);                               % 10MHz = 0.01 GHz
    plot(C(:,1), L10, 'o-', 'LineWidth',0.8, 'MarkerSize',3);
end
set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(devs, 'Location','eastoutside', 'Interpreter','none', 'FontSize',8);
title('パターン1: 既存14機種 (10MHz換算)');
drawnow;   % レイアウト確定（凡例の見切れ防止）
exportgraphics(gcf, 'bench_p1_orig14.png', 'Resolution',300);
fprintf('保存: bench_p1_orig14.png\n');
