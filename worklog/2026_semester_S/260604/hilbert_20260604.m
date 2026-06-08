function R = hilbert_20260604(wav_file)
%====================================================================
% 260604 本番ラン（5区間連続録音）のジッタ自動解析
%
%   1本実行するだけで:
%     ・5区間（kijun / HOLD1 / p3slow / p4avg / gentle）を自動ループ
%     ・各区間の中央 約10秒をヒルベルト変換 → ch間ジッタ差を算出
%     ・スペクトル図と時間波形図を規約名で自動保存
%     ・std を一覧表示 + CSV 保存
%     ・比較図（スペクトル重ね描き / std 棒グラフ）も保存
%
%   解析ロジックは hilbert.m（260521 由来）と同一。窓の位置だけ各区間の
%   中央に合わせる。録音はスクリプトより約10秒先行（offset=+10s）なので、
%   WAV中央時刻 = スクリプト区間中央 + 10s。
%
%   保存ファイル:
%     260604_no<1-5>_<区間>_spectrum.png … スペクトル（0.6Hzピーク確認）
%     260604_no<1-5>_<区間>_jitter.png   … ジッタ時間波形（うねり確認）
%     260604_compare_spectrum.png  … 5区間スペクトル重ね描き
%     260604_compare_std.png       … 区間別 std 棒グラフ
%     260604_jitter_summary.csv    … std / fc / 0.6Hzピーク 一覧
%
%   使い方（Current Folder を 260604 にして実行）:
%     R = hilbert_20260604();                  % 既定 260604_0026.wav
%     R = hilbert_20260604("別名.wav");
%====================================================================

    if nargin < 1 || isempty(wav_file)
        wav_file = "260604_0026.wav";
    end

    %% === 区間定義（中央のWAV時刻[秒] = スクリプト中央 + offset10s）======
    seg_name = {'kijun','HOLD1','p3slow','p4avg','gentle'};
    seg_tc_s = [   160,    460,    760,    1060,   1360 ];   % WAV中央[秒]
    seg_kind = {'FB(基準)','HOLD(基準)','FB(ゆっくり)','FB(平均)','FB(仕上げ)'};
    nseg = numel(seg_name);

    %% === WAV情報・窓 ===================================================
    info = audioinfo(wav_file);
    fs = info.SampleRate;
    fprintf('WAV: %s | fs=%d Hz | ch=%d | %.1f s (%d samples)\n', ...
        wav_file, fs, info.NumChannels, info.Duration, info.TotalSamples);
    if fs ~= 192000
        warning('SampleRate が 192000 ではありません（%d）。解析定数を確認すること。', fs);
    end

    win_pre = 10000;            % hilbert.m と同じ先頭オフセット[サンプル]
    win_len = fs*10 + 20000;    % 解析窓長 ≒ 10.1 s（偶数）
    crop    = 100000;           % 端クロップ[サンプル]

    %% === 結果格納 ======================================================
    R = struct('name',{}, 'tc_s',{}, 'std_s',{}, 'fc_Hz',{}, ...
               'lf_peak_pow',{}, 'lf_peak_freq',{});
    P_all = cell(1, nseg);  f_all = cell(1, nseg);

    %% === 区間ループ ====================================================
    for is = 1:nseg
        name = seg_name{is};
        tc   = seg_tc_s(is);
        s0 = win_pre + tc*fs + 1;
        s1 = win_pre + tc*fs + win_len;

        if s1 > info.TotalSamples
            warning('区間 %s（中央%ds）は録音範囲外のためスキップ（必要%d > 総%d）。', ...
                name, tc, s1, info.TotalSamples);
            continue;
        end

        % --- 区間範囲だけ読み込み（全2GBは読まない）---
        amoto2 = audioread(wav_file, [s0 s1]);
        Nseg = size(amoto2, 1);

        % --- 各chをヒルベルト変換 → ジッタ抽出 ---
        j  = zeros(Nseg, 2);
        fc = zeros(1, 2);
        for ch = 1:2
            aw = amoto2(:, ch);
            N  = numel(aw);
            a2 = fft(aw);
            a2((N/2+2):N) = -a2((N/2+2):N);
            a3 = imag(ifft(a2));
            angle2 = unwrap(angle(aw + 1i*a3));

            X = (1:numel(angle2))';
            A = [sum(X.^2) sum(X); sum(X) numel(X)];
            k = A \ [sum(X.*angle2); sum(angle2)];
            Y2 = X*k(1) + k(2);
            fc(ch) = k(1)*fs/(2*pi);

            jitter = (angle2 - Y2) / (2*pi*48000);   % hilbert.m と同じ換算
            j(:, ch) = bwlimit3(jitter, 0, 12000, fs);
        end

        % --- ch間差・指標 ---
        sa  = j(:,1) - j(:,2);
        sa2 = sa((crop+1):(end-crop));
        P   = abs(fft(sa2)).^2;
        Nf  = numel(sa2);
        freqs = (0:Nf-1)' * fs / Nf;

        lf = (freqs >= 0.2) & (freqs <= 2);          % 0.6Hzハンチング帯
        [lf_pow, ki] = max(P .* lf);
        lf_freq = freqs(ki);

        s_std = std(sa2);
        R(end+1) = struct('name',name, 'tc_s',tc, 'std_s',s_std, ...
            'fc_Hz',mean(fc), 'lf_peak_pow',lf_pow, 'lf_peak_freq',lf_freq); %#ok<AGROW>
        P_all{is} = P;  f_all{is} = freqs;

        fprintf('[%-6s %s] std=%.4g s | LFpeak=%.3g @ %.2f Hz | fc=%.1f Hz\n', ...
            name, seg_kind{is}, s_std, lf_pow, lf_freq, mean(fc));

        % --- 図1: スペクトル ---
        f1 = figure('Name',[name ' spectrum'],'NumberTitle','off','Visible','off');
        plot(freqs, P); set(gca,'yscale','log','xscale','log'); grid on;
        xlabel('freq [Hz]'); ylabel('power');
        title(sprintf('%s (%s)  std=%.3g s', name, seg_kind{is}, s_std));
        exportgraphics(f1, sprintf('260604_no%d_%s_spectrum.png', is, name), 'Resolution', 300);
        close(f1);

        % --- 図2: ジッタ時間波形 ---
        f2 = figure('Name',[name ' jitter'],'NumberTitle','off','Visible','off');
        plot(sa2, '.'); grid on;
        xlabel('sample'); ylabel('jitter diff [s]');
        title(sprintf('%s (%s)  std=%.3g s', name, seg_kind{is}, s_std));
        exportgraphics(f2, sprintf('260604_no%d_%s_jitter.png', is, name), 'Resolution', 300);
        close(f2);
    end

    if isempty(R)
        warning('解析できた区間がありません。WAV長と tc_s を確認。');
        return;
    end

    %% === サマリ表示 + CSV =============================================
    fprintf('\n===== 区間別ジッタ summary =====\n');
    fprintf('%-7s %6s %12s %10s\n', 'seg','tc_s','std[s]','LFpk@Hz');
    for r = 1:numel(R)
        fprintf('%-7s %6d %12.4g %6.3g@%.2f\n', ...
            R(r).name, R(r).tc_s, R(r).std_s, R(r).lf_peak_pow, R(r).lf_peak_freq);
    end
    Tn  = string({R.name})';
    Tbl = table(Tn, [R.tc_s]', [R.std_s]', [R.fc_Hz]', [R.lf_peak_pow]', [R.lf_peak_freq]', ...
        'VariableNames', {'segment','tc_s','std_s','fc_Hz','lf_peak_pow','lf_peak_freq'});
    writetable(Tbl, '260604_jitter_summary.csv');
    fprintf('summary: 260604_jitter_summary.csv\n');

    %% === 比較図: スペクトル重ね描き ===================================
    fc1 = figure('Name','compare spectrum','NumberTitle','off','Visible','off');
    hold on; leg = strings(0,1);
    for is = 1:nseg
        if ~isempty(P_all{is})
            plot(f_all{is}, P_all{is});
            leg(end+1,1) = seg_name{is}; %#ok<AGROW>
        end
    end
    set(gca,'yscale','log','xscale','log'); grid on;
    xlabel('freq [Hz]'); ylabel('power'); legend(leg, 'Location','southwest');
    title('区間別ジッタ差スペクトル比較（左側＝低周波ハンチング）');
    exportgraphics(fc1, '260604_compare_spectrum.png', 'Resolution', 300);
    close(fc1);

    %% === 比較図: std 棒グラフ =========================================
    fc2 = figure('Name','compare std','NumberTitle','off','Visible','off');
    bar([R.std_s]); grid on;
    set(gca, 'XTickLabel', {R.name});
    ylabel('std of jitter diff [s]');
    title('区間別ジッタ差 std（小さいほど良い・HOLD1が基準）');
    % HOLD1 を基準ラインに
    ih = find(strcmp({R.name},'HOLD1'), 1);
    if ~isempty(ih)
        yline(R(ih).std_s, 'r--', 'HOLD1');
    end
    exportgraphics(fc2, '260604_compare_std.png', 'Resolution', 300);
    close(fc2);

    fprintf('\n比較図: 260604_compare_spectrum.png / 260604_compare_std.png\n');
    fprintf('完了。\n');
end
