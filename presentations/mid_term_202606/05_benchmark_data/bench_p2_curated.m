% bench_p2_curated.m
% パターン2: 既存14機種 + 各カテゴリ代表（追加分から1〜2機種）を 10MHz 換算で重ね描き
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p2_curated
% 出力: bench_p2_curated.png
% 注: 既存14も追加代表も対等に色つきで表示（凡例も個別）。重複回避のため
%     PRS10・iMaser は既存14に含まれるので追加しない。代表は下の pick を編集。

xlsx = "dBCperHz.xlsx";
ex14 = ["Ceyear2G","Ceyear3G","DST2","DST1","SPXONo1","OEO","Abracon-U", ...
        "EPSON-VCSO","TCXO-CMOS","iMaser-10MLN","PRS10","DST-24.576", ...
        "cybershaft(638000円)","cybershaft(121,000円)"];

% 各カテゴリ代表（benchmark_extra_data.m の name と一致させること）
pick = ["Abracon AOCJY", ...                 % OCXO 標準
        "Oscilloquartz 8788/8789 ULN", ...    % OCXO 高性能
        "Microchip 5071A Cs @10MHz", ...      % セシウム
        "Leo Bodnar GPSDO", ...               % GPSDO
        "SiTime SiT5356 (MEMS)", ...          % MEMS
        "Epson TG2520SMN (TCXO)"];            % TCXO

figure('Name','P2 既存14+代表 (10MHz換算)','NumberTitle','off','Position',[40 40 1500 760]);
hold on;

legH = []; legL = strings(0,1);

% --- 既存14（対等・色つき）---
for i = 1:numel(ex14)
    d = ex14(i);
    N = cell2mat(readcell(xlsx,"Sheet",d,"Range","A3:A3"));
    f = cell2mat(readcell(xlsx,"Sheet",d,"Range","A2:A2"));
    C = cell2mat(readcell(xlsx,"Sheet",d,"Range",strcat("A4:B",num2str(3+N))));
    L10 = C(:,2) + 20*log10(0.01 ./ f);
    h = plot(C(:,1), L10, 'o-', 'LineWidth',1.0, 'MarkerSize',3);
    legH(end+1) = h; legL(end+1) = d; %#ok<AGROW>
end

% --- 追加代表（対等・色つき）---
D = benchmark_extra_data();
allnames = string({D.name});
for k = 1:numel(pick)
    idx = find(allnames == pick(k), 1);
    if isempty(idx)
        warning('benchmark_extra_data に見つからない: %s', pick(k)); continue;
    end
    d = D(idx);
    L10 = d.L + 20*log10(10 ./ d.carrier_MHz);
    h = plot(d.off, L10, 'o-', 'LineWidth',1.0, 'MarkerSize',3);
    legH(end+1) = h; legL(end+1) = string(d.name); %#ok<AGROW>
end

set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(legH, legL, 'Location','eastoutside', 'Interpreter','none', 'FontSize',8);
title('パターン2: 既存14 + 各カテゴリ代表 (10MHz換算)');
drawnow;   % レイアウト確定（凡例の見切れ防止）
exportgraphics(gcf, 'bench_p2_curated.png', 'Resolution',300);
fprintf('保存: bench_p2_curated.png\n');
