function compare_jitter_260610(varargin)
%====================================================================
% 260610 制御方式 横断比較 → **位相雑音 dBc/Hz 重ね描き**（主結果の図）
%
%   analyze_jitter_260610 が返す R を複数渡すと、各方式・各区間の
%   位相雑音 L(f) [dBc/Hz] を **1枚に重ね描き** し、低周波（~0.6Hz
%   ハンチング帯）がどの制御で低いかを一目で比較する。
%   ＝「各制御で hilbert の低Hzノイズ（dBc/Hz）が低いか」を答える図。
%
%   ※ 'acq'（ウォームアップ）区間は比較から除外。HOLD は点線で区別。
%
%   保存:
%     260610_compare_PN.png       … 位相雑音 dBc/Hz 重ね描き（semilogx）
%     260610_compare_summary.csv  … 方式×区間の std / 低周波ピーク[dBc/Hz]
%
%   使い方:
%     Rp = analyze_jitter_260610("rec_pid.wav",   "..._segmap.csv", 10, "pid");
%     Rm = analyze_jitter_260610("rec_model.wav", "..._segmap.csv", 12, "model");
%     compare_jitter_260610(Rp, Rm);
%====================================================================
    if nargin < 1, error('analyze_jitter_260610 の返り値 R を1つ以上渡してください。'); end

    % --- 比較対象（acq除外）を平坦化 ---
    items = struct('label',{}, 'tag',{}, 'name',{}, 'mode',{}, ...
                   'std_s',{}, 'lf_peak_dbc',{}, 'lf_peak_freq',{}, 'f',{}, 'Lf',{});
    for a = 1:nargin
        R = varargin{a};
        if ~isfield(R,'specs') || isempty(R.specs), continue; end
        for is = 1:numel(R.specs)
            sp = R.specs(is);
            if strcmpi(sp.name,'acq'), continue; end
            items(end+1) = struct('label',sprintf('%s:%s', R.tag, sp.name), ...
                'tag',R.tag, 'name',char(sp.name), 'mode',char(sp.mode), ...
                'std_s',sp.std_s, 'lf_peak_dbc',sp.lf_peak_dbc, ...
                'lf_peak_freq',sp.lf_peak_freq, 'f',sp.f, 'Lf',sp.Lf); %#ok<AGROW>
        end
    end
    if isempty(items), error('比較できる区間がありません（specs が空）。'); end
    nit = numel(items);

    %% === 図: 位相雑音 dBc/Hz 重ね描き =================================
    f1 = figure('Name','compare PN','NumberTitle','off','Visible','off','Position',[80 80 860 540]);
    hold on; leg = strings(0,1); h = gobjects(1,nit);
    for i = 1:nit
        ls = '-'; if strcmpi(items(i).mode,'HOLD'), ls = '--'; end   % HOLDは点線
        h(i) = semilogx(items(i).f, items(i).Lf, ls, 'LineWidth',1.0);
        leg(end+1,1) = items(i).label; %#ok<AGROW>
    end
    set(gca,'xscale','log'); grid on;
    xlim([0.05 50]);
    xlabel('offset frequency [Hz]'); ylabel('L(f) [dBc/Hz]');
    xline(0.6, 'k:', '0.6Hz', 'HandleVisibility','off');   % 凡例に出さない
    legend(h, leg, 'Location','northeast', 'Interpreter','none');
    title('制御方式×区間 位相雑音 L(f) 比較（低周波が低いほど良い・HOLD=点線）');
    exportgraphics(f1, '260610_compare_PN.png', 'Resolution', 300);
    close(f1);

    %% === サマリ CSV + コンソール ======================================
    Tbl = table(string({items.label})', string({items.mode})', [items.std_s]', ...
        [items.lf_peak_dbc]', [items.lf_peak_freq]', ...
        'VariableNames', {'label','mode','std_s','lf_peak_dBcHz','lf_peak_freq'});
    writetable(Tbl, '260610_compare_summary.csv');

    fprintf('\n===== 横断比較 summary（低周波 0.2-2Hz ピーク）=====\n');
    fprintf('%-16s %-6s %12s %14s\n','label','mode','std[s]','LFpk[dBc/Hz]');
    for i = 1:nit
        fprintf('%-16s %-6s %12.4g %10.1f @%.2fHz\n', items(i).label, items(i).mode, ...
            items(i).std_s, items(i).lf_peak_dbc, items(i).lf_peak_freq);
    end
    [~, ib] = min([items.lf_peak_dbc]);
    fprintf('\n>>> 低周波ピーク最小（勝ち筋）: %s  %.1f dBc/Hz\n', items(ib).label, items(ib).lf_peak_dbc);
    fprintf('図: 260610_compare_PN.png | CSV: 260610_compare_summary.csv\n');
end
