function overlay_benchmark_10MHz(Rmodel, kpe_name)
%====================================================================
% 市販ベンチマーク位相雑音（dBCperHz.xlsx 全機種, 10MHz換算）に、
% 260610で測定した 本研究の モデルFB(Kp_e=0.08) と HOLD を重ね描きする。
%
%   ・excelyomi.m と同じ14シートを読み、すべて 10MHz に換算してplot
%       L_10MHz = L_f + 20*log10(0.01[GHz] / f_carrier[GHz])
%   ・本研究の測定は analyze_jitter_260610 の返り値(Am)から
%       kpe0.08 と HOLD の L(f)[dBc/Hz] を太線で重ねる
%       ※ 本研究の曲線は「2台のOCXOの差(相対位相雑音, 10MHz基準)」
%
%   使い方（Current Folder を本フォルダ=dBCperHz.xlsx のある所に）:
%     % まず 260610 で測定結果を得る（無ければ）:
%     %   Am = analyze_jitter_260610("260610_exp2.wav", ...
%     %         "frfr_model_20260610_160859_segmap.csv", 10, "model");
%     overlay_benchmark_10MHz(Am);            % 既定 kpe0.08
%     overlay_benchmark_10MHz(Am, "kpe0.04"); % 別Kp_eを重ねる
%     overlay_benchmark_10MHz();              % 市販ベンチマークのみ
%
%   保存: 260611_benchmark_10MHz_overlay.png
%====================================================================
    if nargin < 2 || isempty(kpe_name), kpe_name = "kpe0.08"; end
    kpe_name = string(kpe_name);
    xlsx  = "dBCperHz.xlsx";
    kijun = 0.01;            % 10MHz換算 [GHz]

    % excelyomi と同じ機種・順序
    devs = ["Ceyear2G","Ceyear3G","DST2","DST1","SPXONo1","OEO", ...
            "Abracon-U","EPSON-VCSO","TCXO-CMOS","iMaser-10MLN","PRS10", ...
            "DST-24.576","cybershaft(638000円)","cybershaft(121,000円)"];

    fig = figure('Name','benchmark 10MHz overlay','NumberTitle','off','Position',[60 60 1000 620]);
    hold on; leg = strings(0,1);

    %% === 市販ベンチマーク（10MHz換算, 細い灰色系）====================
    for i = 1:numel(devs)
        d = devs(i);
        try
            N = cell2mat(readcell(xlsx,"Sheet",d,"Range","A3:A3"));
            f = cell2mat(readcell(xlsx,"Sheet",d,"Range","A2:A2"));   % 搬送波[GHz]
            C = cell2mat(readcell(xlsx,"Sheet",d,"Range",strcat("A4:B",num2str(3+N))));
        catch ME
            warning("シート %s 読み込み失敗: %s", d, ME.message); continue;
        end
        off = C(:,1);
        L10 = C(:,2) + 20*log10(kijun/f);     % 10MHz換算
        plot(off, L10, 'o-', 'LineWidth', 0.8, 'MarkerSize', 3);
        leg(end+1,1) = d; %#ok<AGROW>
    end

    %% === 本研究の測定（太線で重ねる）================================
    if nargin >= 1 && ~isempty(Rmodel) && isfield(Rmodel,'specs')
        S = Rmodel.specs;
        names = string({S.name});
        modes = string({S.mode});
        i_fb   = find(names == kpe_name, 1);
        i_hold = find(strcmpi(modes,'HOLD'), 1);
        if ~isempty(i_fb)
            plot(S(i_fb).f, S(i_fb).Lf, 'k-', 'LineWidth', 2.2);
            leg(end+1,1) = sprintf("本研究 モデルFB(%s) [2台差]", kpe_name); %#ok<AGROW>
        end
        if ~isempty(i_hold)
            plot(S(i_hold).f, S(i_hold).Lf, 'k--', 'LineWidth', 2.2);
            leg(end+1,1) = "本研究 HOLD [2台差]"; %#ok<AGROW>
        end
        if isempty(i_fb) && isempty(i_hold)
            warning("Rmodel.specs に %s / HOLD が見つかりません。", kpe_name);
        end
    else
        fprintf("（本研究データなし: 市販ベンチマークのみ表示。Am を渡すと重ね描きします）\n");
    end

    %% === 体裁 ========================================================
    set(gca,'xscale','log'); grid on;
    xlim([0.1 1e6]);
    xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
    legend(leg, 'Location','northeastoutside', 'Interpreter','none', 'FontSize',8);
    title('市販ベンチマーク位相雑音(10MHz換算) と 本研究の測定 重ね描き');
    % 注記: 本研究は2台差(相対)。単体推定は約 -3 dB。
    text(0.12, min(ylim)+5, '※ 本研究の曲線は2台OCXOの差(相対)。単体推定は約-3 dB。', ...
        'FontSize',8, 'VerticalAlignment','bottom');

    exportgraphics(fig, '260611_benchmark_10MHz_overlay.png', 'Resolution', 300);
    fprintf("保存: 260611_benchmark_10MHz_overlay.png\n");
end
