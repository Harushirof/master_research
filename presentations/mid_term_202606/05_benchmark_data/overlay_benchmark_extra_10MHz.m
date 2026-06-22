function overlay_benchmark_extra_10MHz(Rmodel, kpe_name)
% （旧 overlay_benchmark_full_10MHz をリネーム。内容同一: 追加43機種 + 本研究2）
%====================================================================
% フル・ベンチマーク重ね描き（10MHz換算）+ 本研究の測定
%
%   benchmark_extra_data.m の市販/公開43機種を 10MHz に換算し、
%   発振器の種別(OCXO/Rb/Cs/H-maser/GPSDO/MEMS/TCXO)で色分けして重ね描き。
%   さらに 260610 の モデルFB(Kp_e=0.08) と HOLD を太い黒線で重ねる。
%       L_10MHz = L_carrier + 20*log10(10 / carrier_MHz)
%       本研究の曲線は2台OCXOの差(相対, 10MHz基準)
%
%   使い方（dBCperHz.xlsx と同じフォルダで）:
%     Am = analyze_jitter_260610("260610_exp2.wav", ...
%            "frfr_model_20260610_160859_segmap.csv", 10, "model");  % 無ければ
%     overlay_benchmark_full_10MHz(Am);
%     overlay_benchmark_full_10MHz();   % 市販ベンチマークのみ
%
%   保存: 260611_benchmark_extra_10MHz.png
%====================================================================
    if nargin < 2 || isempty(kpe_name), kpe_name = "kpe0.08"; end
    kpe_name = string(kpe_name);

    D = benchmark_extra_data();

    % 種別→色
    types = ["OCXO","Rb","Cs","H-maser","GPSDO","MEMS","TCXO"];
    cols  = [0.85 0.33 0.10;   % OCXO 橙
             0.00 0.45 0.74;   % Rb   青
             0.47 0.67 0.19;   % Cs   緑
             0.49 0.18 0.56;   % maser紫
             0.30 0.75 0.93;   % GPSDO水
             0.64 0.08 0.18;   % MEMS 赤
             0.50 0.50 0.50];  % TCXO 灰
    typeShown = false(1,numel(types));

    fig = figure('Name','benchmark full 10MHz','NumberTitle','off','Position',[50 50 1080 650]);
    hold on; legH = []; legL = strings(0,1);

    %% === 市販/公開ベンチマーク（10MHz換算, 種別色）====================
    for i = 1:numel(D)
        d = D(i);
        L10 = d.L + 20*log10(10 / d.carrier_MHz);    % 10MHz換算
        ti = find(types == string(d.type), 1);
        if isempty(ti), ti = numel(types); end
        c = cols(ti,:);
        h = plot(d.off, L10, 'o-', 'Color', c, 'LineWidth', 0.7, 'MarkerSize', 3);
        if ~typeShown(ti)
            legH(end+1) = h; legL(end+1,1) = types(ti); %#ok<AGROW>
            typeShown(ti) = true;
        end
    end

    %% === 本研究の測定（太い黒線）====================================
    if nargin >= 1 && ~isempty(Rmodel) && isfield(Rmodel,'specs')
        S = Rmodel.specs; names = string({S.name}); modes = string({S.mode});
        i_fb = find(names == kpe_name, 1); i_hold = find(strcmpi(modes,'HOLD'),1);
        if ~isempty(i_fb)
            h = plot(S(i_fb).f, S(i_fb).Lf, 'k-', 'LineWidth', 2.4);
            legH(end+1) = h; legL(end+1,1) = sprintf("本研究 モデルFB(%s)[2台差]", kpe_name); %#ok<AGROW>
        end
        if ~isempty(i_hold)
            h = plot(S(i_hold).f, S(i_hold).Lf, 'k--', 'LineWidth', 2.4);
            legH(end+1) = h; legL(end+1,1) = "本研究 HOLD[2台差]"; %#ok<AGROW>
        end
    else
        fprintf("（本研究データなし: ベンチマークのみ。Am を渡すと重ねます）\n");
    end

    %% === 体裁 ========================================================
    set(gca,'xscale','log'); grid on;
    xlim([0.1 1e6]); ylim([-170 -30]);
    xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz] (10MHz換算)');
    legend(legH, legL, 'Location','northeastoutside', 'Interpreter','none', 'FontSize',9);
    title('市販/公開ベンチマーク(43機種, 10MHz換算, 種別色) と 本研究の測定');
    text(0.12, -165, '※ 本研究は2台OCXOの差(相対)。単体推定は約-3 dB。市販は単体・データシート値(一部spec上限)。', ...
        'FontSize',8);

    exportgraphics(fig, '260611_benchmark_extra_10MHz.png', 'Resolution', 300);
    fprintf("保存: 260611_benchmark_extra_10MHz.png  (機種数=%d)\n", numel(D));
end
