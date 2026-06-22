% bench_p4_all43.m
% パターン4: 既存14(dBCperHz.xlsx) ＋ 追加43(benchmark_extra_data) = 全部 を
%            10MHz 換算・種別色で重ね描き
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p4_all43
% 出力: bench_p4_all43.png
% 注: 重複機種(PRS10, cybershaft x2)は追加側(データシート)を採用し、既存14側を除外。
%     既存14は搬送波がバラバラなので種別を割当て(SG/OEO/VCSO/XO を追加カテゴリ)。
%     ※ 既存14の種別は便宜的分類（Abracon-U等は概略）。

xlsx = "dBCperHz.xlsx";
D = benchmark_extra_data();

% 種別→色（追加7種 + 既存14用に SG/OEO/VCSO/XO を追加）
types = ["OCXO","Rb","Cs","H-maser","GPSDO","MEMS","TCXO","SG","OEO","VCSO","XO"];
cols  = [0.85 0.33 0.10;   % OCXO
         0.00 0.45 0.74;   % Rb
         0.47 0.67 0.19;   % Cs
         0.49 0.18 0.56;   % H-maser
         0.30 0.75 0.93;   % GPSDO
         0.64 0.08 0.18;   % MEMS
         0.50 0.50 0.50;   % TCXO
         0.93 0.69 0.13;   % SG（信号発生器）
         0.15 0.15 0.15;   % OEO
         0.85 0.33 0.70;   % VCSO
         0.10 0.55 0.45];  % XO

% 既存14シート → 種別割当て（重複3つ PRS10/cybershaft x2 は除外）
ex14     = ["Ceyear2G","Ceyear3G","DST2","DST1","SPXONo1","OEO","Abracon-U", ...
            "EPSON-VCSO","TCXO-CMOS","iMaser-10MLN","DST-24.576"];
ex14type = ["SG","SG","SG","SG","XO","OEO","XO", ...
            "VCSO","TCXO","H-maser","XO"];

figure('Name','P4 全部 (10MHz換算)','NumberTitle','off','Position',[40 40 1500 760]);
hold on;
shown = false(1,numel(types)); legH = []; legL = strings(0,1);

% --- 追加43（種別色）---
for i = 1:numel(D)
    d = D(i);
    L10 = d.L + 20*log10(10 ./ d.carrier_MHz);
    ti = find(types == string(d.type), 1); if isempty(ti), ti = numel(types); end
    h = plot(d.off, L10, 'o-', 'Color',cols(ti,:), 'LineWidth',0.8, 'MarkerSize',3);
    if ~shown(ti), legH(end+1)=h; legL(end+1,1)=types(ti); shown(ti)=true; end %#ok<AGROW>
end

% --- 既存14（種別色, xlsx）---
for i = 1:numel(ex14)
    d = ex14(i);
    N = cell2mat(readcell(xlsx,"Sheet",d,"Range","A3:A3"));
    f = cell2mat(readcell(xlsx,"Sheet",d,"Range","A2:A2"));            % 搬送波 [GHz]
    C = cell2mat(readcell(xlsx,"Sheet",d,"Range",strcat("A4:B",num2str(3+N))));
    L10 = C(:,2) + 20*log10(0.01 ./ f);                               % 10MHz = 0.01 GHz
    ti = find(types == ex14type(i), 1); if isempty(ti), ti = numel(types); end
    h = plot(C(:,1), L10, 'o-', 'Color',cols(ti,:), 'LineWidth',0.8, 'MarkerSize',3);
    if ~shown(ti), legH(end+1)=h; legL(end+1,1)=ex14type(i); shown(ti)=true; end %#ok<AGROW>
end

set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(legH, legL, 'Location','eastoutside', 'FontSize',9);
title('パターン4: 全部（既存14 ＋ 追加43, 種別色, 10MHz換算）');
drawnow;   % レイアウト確定（凡例の見切れ防止）
exportgraphics(gcf, 'bench_p4_all43.png', 'Resolution',300);
fprintf('保存: bench_p4_all43.png (既存%d + 追加%d = %d系列)\n', numel(ex14), numel(D), numel(ex14)+numel(D));
