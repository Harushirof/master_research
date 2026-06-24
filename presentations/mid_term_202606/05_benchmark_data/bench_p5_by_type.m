% bench_p5_by_type.m
% パターン5: 種別ごとの代表機種を 10MHz 換算で重ね描き（種類でジッタがどう違うか）。
% OCXO は研究対象なので 3 機種（性能の異なる代表）を出して幅を見せる。
%
% 実行方法（このフォルダ 05_benchmark_data で）:
%   >> bench_p5_by_type
% 出力: bench_p5_by_type.png
%
% 代表を変えるなら pick_name/pick_label/pick_col を編集（name はカタログ
% benchmark_extra_data の name と一致）。本研究(k=0.08/HOLD)を重ねるなら末尾 OVERLAY。
% ※ 実験で使用中の OCXO は "CTI" 製。現データセットには未収録（追加するなら別途）。

D = benchmark_extra_data();
allnames = string({D.name});

% --- 代表（name, 凡例ラベル, 色）---  OCXO は 3 機種
pick_name = [ ...
    "Abracon AOCJY", ...                    % OCXO
    "Morion MV89A", ...                     % OCXO (5MHz→10MHz換算)
    "Oscilloquartz 8607 Std", ...           % OCXO
    "Microchip 8040C LN (Rb)", ...          % Rb
    "Microchip 5071A Cs @10MHz", ...        % Cs
    "T4Science iMaser3000 Std @5MHz", ...   % 水素メーザー
    "Leo Bodnar GPSDO", ...                 % GPSDO
    "Microchip SA.45s CSAC", ...            % CSAC
    "SiTime SiT5356 (MEMS)", ...            % MEMS
    "Epson TG2520SMN (TCXO)"];              % TCXO
pick_label = [ ...
    "OCXO (Abracon AOCJY)", ...
    "OCXO (Morion MV89A)", ...
    "OCXO (Oscilloquartz 8607)", ...
    "Rb (Microchip 8040C LN)", ...
    "Cs一次標準 (5071A)", ...
    "水素メーザー (iMaser3000)", ...
    "GPSDO (Leo Bodnar)", ...
    "CSAC チップ原子 (SA.45s)", ...
    "MEMS (SiTime SiT5356)", ...
    "TCXO (Epson TG2520SMN)"];
pick_col = [ ...
    0.93 0.69 0.13;   % OCXO  金橙
    0.85 0.33 0.10;   % OCXO  橙
    0.60 0.20 0.00;   % OCXO  茶
    0.00 0.45 0.74;   % Rb    青
    0.47 0.67 0.19;   % Cs    緑
    0.49 0.18 0.56;   % maser 紫
    0.30 0.75 0.93;   % GPSDO 水
    0.00 0.00 0.00;   % CSAC  黒
    0.64 0.08 0.18;   % MEMS  暗赤
    0.50 0.50 0.50];  % TCXO  灰

figure('Name','P5 種別代表 (10MHz換算)','NumberTitle','off','Position',[40 40 1500 760]);
hold on; legH = []; legL = strings(0,1);

for k = 1:numel(pick_name)
    idx = find(allnames == pick_name(k), 1);
    if isempty(idx)
        warning('benchmark_extra_data に見つからない: %s', pick_name(k)); continue;
    end
    d = D(idx);
    L10 = d.L + 20*log10(10 ./ d.carrier_MHz);          % 10MHz 換算
    h = plot(d.off, L10, 'o-', 'Color',pick_col(k,:), 'LineWidth',1.8, 'MarkerSize',5);
    legH(end+1) = h; legL(end+1,1) = pick_label(k); %#ok<AGROW>
end

% ===== OVERLAY: 本研究の測定(k=0.08 / HOLD)を重ねる場合は以下を有効化 =====
% Am = analyze_jitter_260610("..\..\..\worklog\2026_semester_S\260610\260610_exp2.wav", ...
%        "..\..\..\worklog\2026_semester_S\260610\frfr_model_20260610_160859_segmap.csv", 10, "model");
% S = Am.specs; nm = string({S.name}); md = string({S.mode});
% i1 = find(nm=="kpe0.08",1); i2 = find(strcmpi(md,'HOLD'),1);
% if ~isempty(i1), h=plot(S(i1).f,S(i1).Lf,'k-','LineWidth',2.4); legH(end+1)=h; legL(end+1,1)="本研究 モデルFB(0.08)[2台差]"; end
% if ~isempty(i2), h=plot(S(i2).f,S(i2).Lf,'k--','LineWidth',2.4); legH(end+1)=h; legL(end+1,1)="本研究 HOLD[2台差]"; end

set(gca,'xscale','log'); grid on;
xlim([0.1 1e6]); ylim([-170 -30]);
xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
legend(legH, legL, 'Location','eastoutside', 'Interpreter','none', 'FontSize',10);
title('パターン5: 主要発振器の種別比較（10MHz換算 位相雑音）');
drawnow;
exportgraphics(gcf, 'bench_p5_by_type.png', 'Resolution',300);
fprintf('保存: bench_p5_by_type.png (%d系列)\n', numel(legL));
