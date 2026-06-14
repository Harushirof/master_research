function compare_kpe08_hold_260610(Rmodel, kpe_name)
%====================================================================
% 中間発表メイン図: 実測モデルFB(Kp_e=0.08) vs 無制御HOLD の位相雑音比較
%
%   analyze_jitter_260610 の model 返り値（Am）から、指定 Kp_e 区間と HOLD
%   の2本だけを dBc/Hz で重ね描きする（発表スライド用のクリーン版）。
%
%   使い方:
%     Am = analyze_jitter_260610("260610_exp2.wav", "frfr_model_..._segmap.csv", 10, "model");
%     compare_kpe08_hold_260610(Am);              % 既定 kpe0.08
%     compare_kpe08_hold_260610(Am, "kpe0.04");   % 別Kp_eと比べたい時
%
%   保存: 260610_kpe08_vs_hold.png
%====================================================================
    if nargin < 1 || ~isfield(Rmodel,'specs'), error('analyze_jitter_260610 の返り値(model)を渡してください。'); end
    if nargin < 2 || isempty(kpe_name), kpe_name = "kpe0.08"; end
    kpe_name = string(kpe_name);

    S = Rmodel.specs;
    names = string({S.name});
    modes = string({S.mode});
    i_fb   = find(names == kpe_name, 1);
    i_hold = find(strcmpi(modes,'HOLD'), 1);
    if isempty(i_fb),   error('区間 %s が見つかりません。', kpe_name); end
    if isempty(i_hold), error('HOLD 区間が見つかりません。'); end

    fb = S(i_fb);  hd = S(i_hold);

    f1 = figure('Name','kpe08 vs HOLD','NumberTitle','off','Position',[80 80 820 520]);
    semilogx(fb.f, fb.Lf, 'b-',  'LineWidth',1.4); hold on;
    semilogx(hd.f, hd.Lf, 'r--', 'LineWidth',1.4);
    grid on; xlim([0.05 50]);
    xlabel('オフセット周波数 [Hz]'); ylabel('L(f) [dBc/Hz]');
    xline(0.6, 'k:', '0.6 Hz', 'HandleVisibility','off');
    legend({sprintf('実測モデルFB (%s)  std=%.0f ps', kpe_name, fb.std_s*1e12), ...
            sprintf('無制御 HOLD          std=%.0f ps', hd.std_s*1e12)}, ...
           'Location','northeast', 'Interpreter','none');
    title(sprintf('実測モデルFB vs 無制御 — 相対位相雑音 (f0=%.0f MHz, 2台差)', Rmodel.f0/1e6));

    % 低周波(0.2-2Hz)の差を注記
    bd = (fb.f>=0.2 & fb.f<=2);
    dlt = max(fb.Lf(bd)) - max(hd.Lf(bd));
    text(0.06, min(fb.Lf)+3, sprintf('低周波(0.2-2Hz)差 ≈ %.1f dB\n（≈0 なら注入なし＝HOLD並み）', dlt), ...
        'FontSize',9, 'VerticalAlignment','bottom');

    exportgraphics(f1, '260610_kpe08_vs_hold.png', 'Resolution', 300);
    fprintf('保存: 260610_kpe08_vs_hold.png | FB(%s) std=%.1f ps / HOLD std=%.1f ps | 低周波差≈%.1f dB\n', ...
        kpe_name, fb.std_s*1e12, hd.std_s*1e12, dlt);
end
