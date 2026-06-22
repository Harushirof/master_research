function overlay_benchmark_all_10MHz(Rmodel, kpe_name)
%====================================================================
% 全部入り重ね描き（10MHz換算）: 既存14(xlsx) + 追加43 + 本研究2
%
%   3系統をすべて 10MHz に換算して1枚に重ねる:
%     (1) 既存14: dBCperHz.xlsx の各シート（重複機種は除外）→ 灰色細点線
%     (2) 追加43: benchmark_extra_data.m → 種別色（OCXO/Rb/Cs/maser/GPSDO/MEMS/TCXO）
%     (3) 本研究2: 260610 モデルFB(Kp_e=0.08) と HOLD → 太い黒線
%       L_10MHz = L_carrier + 20*log10(10 / carrier_MHz)
%       本研究は2台OCXOの差(相対, 10MHz基準)
%
%   重複除外: xlsx と 追加43 で重なる機種は「追加(データシート)側を優先」し、
%   xlsx 側の該当シートをスキップ（既定: PRS10, cybershaft×2）。
%   ※ iMaser は xlsx=10MHz / 追加=5・100MHz と搬送波が異なるため両方残す。
%
%   使い方（dBCperHz.xlsx と同じフォルダで）:
%     Am = analyze_jitter_260610("260610_exp2.wav", ...
%            "frfr_model_20260610_160859_segmap.csv", 10, "model");  % 無ければ
%     overlay_benchmark_all_10MHz(Am);
%     overlay_benchmark_all_10MHz();   % 市販のみ
%
%   保存: 260611_benchmark_all_10MHz.png
%====================================================================
    if nargin < 2 || isempty(kpe_name), kpe_name = "kpe0.08"; end
    kpe_name = string(kpe_name);
    xlsx = "dBCperHz.xlsx";

    % xlsx 全14シート（excelyomi と同じ）
    xlsx_devs = ["Ceyear2G","Ceyear3G","DST2","DST1","SPXONo1","OEO", ...
                 "Abracon-U","EPSON-VCSO","TCXO-CMOS","iMaser-10MLN","PRS10", ...
                 "DST-24.576","cybershaft(638000円)","cybershaft(121,000円)"];
    % 追加43と重複 → xlsx側をスキップ（追加=データシート側を優先）
    skip = ["PRS10","cybershaft(638000円)","cybershaft(121,000円)"];

    % 種別→色
    types = ["OCXO","Rb","Cs","H-maser","GPSDO","MEMS","TCXO"];
    cols  = [0.85 0.33 0.10; 0.00 0.45 0.74; 0.47 0.67 0.19; 0.49 0.18 0.56; ...
             0.30 0.75 0.93; 0.64 0.08 0.18; 0.50 0.50 0.50];
    typeShown = false(1,numel(types));

    fig = figure('Name','benchmark ALL 10MHz','NumberTitle','off','Position',[40 40 1120 680]);
    hold on; legH = []; legL = strings(0,1);  xlsxShown = false;

    %% === (1) 既存14（xlsx, 重複除外）: 灰色細点線 ====================
    for i = 1:numel(xlsx_devs)
        d = xlsx_devs(i);
        if any(d == skip), continue; end
        try
            N = cell2mat(readcell(xlsx,"Sheet",d,"Range","A3:A3"));
            f = cell2mat(readcell(xlsx,"Sheet",d,"Range","A2:A2"));
            C = cell2mat(readcell(xlsx,"Sheet",d,"Range",strcat("A4:B",num2str(3+N))));
        catch ME
            warning("xlsx %s 読込失敗: %s", d, ME.message); continue;
        end
        L10 = C(:,2) + 20*log10(0.01/f);   % f は GHz, 0.01GHz=10MHz
        h = plot(C(:,1), L10, ':', 'Color',[0.6 0.6 0.6], 'LineWidth',0.6);
        if ~xlsxShown
            legH(end+1)=h; legL(end+1,1)="既存xlsx(重複除外)"; xlsxShown=true; %#ok<AGROW>
        end
    end

    %% === (2) 追加43: 種別色 ==========================================
    D = benchmark_extra_data();
    for i = 1:numel(D)
        d = D(i);
        L10 = d.L + 20*log10(10 / d.carrier_MHz);
        ti = find(types == string(d.type), 1); if isempty(ti), ti = numel(types); end
        h = plot(d.off, L10, 'o-', 'Color',cols(ti,:), 'LineWidth',0.7, 'MarkerSize',3);
        if ~typeShown(ti)
            legH(end+1)=h; legL(end+1,1)=types(ti); typeShown(ti)=true; %#ok<AGROW>
        end
    end

    %% === (3) 本研究2: 太い黒線 =======================================
    if nargin >= 1 && ~isempty(Rmodel) && isfield(Rmodel,'specs')
        S = Rmodel.specs; names = string({S.name}); modes = string({S.mode});
        i_fb = find(names == kpe_name, 1); i_hold = find(strcmpi(modes,'HOLD'),1);
        if ~isempty(i_fb)
            h = plot(S(i_fb).f, S(i_fb).Lf, 'k-', 'LineWidth',2.6);
            legH(end+1)=h; legL(end+1,1)=sprintf("本研究 モデルFB(%s)[2台差]",kpe_name); %#ok<AGROW>
        end
        if ~isempty(i_hold)
            h = plot(S(i_hold).f, S(i_hold).Lf, 'k--', 'LineWidth',2.6);
            legH(end+1)=h; legL(end+1,1)="本研究 HOLD[2台差]"; %#ok<AGROW>
        end
    else
        fprintf("（本研究データなし: 市販のみ。Am を渡すと重ねます）\n");
    end

    %% === 体裁 ========================================================
    set(gca,'xscale','log'); grid on;
    xlim([0.1 1e6]); ylim([-170 -30]);
    xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
    legend(legH, legL, 'Location','northeastoutside', 'Interpreter','none', 'FontSize',9);
    title('全ベンチマーク(既存xlsx + 追加43, 10MHz換算) と 本研究の測定');
    text(0.12, -165, '※ 本研究は2台差(相対)。単体推定は約-3dB。重複機種はデータシート(追加)側を採用。', 'FontSize',8);

    exportgraphics(fig, '260611_benchmark_all_10MHz.png', 'Resolution',300);
    fprintf("保存: 260611_benchmark_all_10MHz.png (xlsx除外:%s)\n", strjoin(skip,', '));
end
