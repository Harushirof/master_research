function R = analyze_jitter_260608(wav_file, segmap_csv, offset_s)
%====================================================================
% 260608 録音(WAV)の区間別ジッタ自動解析  ── ps級の精度評価
%
%   hilbert_20260604.m の解析ロジック（hilbert + bwlimit3）をそのまま使い、
%   区間中央時刻のハードコードをやめて **segmap.csv から自動計算** する汎用版。
%   gainsweep / model どちらのランでもそのまま解析できる。
%   ※ bwlimit3.m が同フォルダ（または path）に必要。
%
%   各区間で:
%     ・WAV中央時刻 ≒ (区間中央のスクリプト時刻) + offset_s
%     ・中央 約10s をヒルベルト変換 → 2ch のジッタ差 → bwlimit3 で帯域制限
%     ・std [s]（小さいほど良い）、0.2-2Hz の低周波ピーク（ハンチング）を算出
%
%   入力:
%     wav_file    録音WAV（48k〜192k想定。元コードは192kHz前提の定数）
%     segmap_csv  実験スクリプトが出した *_segmap.csv（name,mode,t_start,t_end列）
%     offset_s    スクリプト t=0 が WAV 上で何秒か
%                 = (スクリプト t=0 の絶対時刻) − (録音開始の絶対時刻)
%                 例: 録音を先に10秒回してからスクリプト開始 → offset_s = +10
%
%   自動保存（<base>=WAVのベース名）:
%     <base>_<seg>_spectrum.png … 区間別スペクトル（低周波＝ハンチング）
%     <base>_<seg>_jitter.png   … 区間別ジッタ差 時間波形
%     <base>_compare_spectrum.png … 全区間スペクトル重ね描き
%     <base>_compare_std.png      … 区間別 std 棒グラフ（HOLD基準線）
%     <base>_jitter_summary.csv   … std / fc / 低周波ピーク 一覧
%
%   使い方（Current Folder を 260608 に）:
%     R = analyze_jitter_260608("rec.wav", "frfr_model_20260608_141000_segmap.csv", 10);
%====================================================================
    if nargin < 1 || isempty(wav_file),   error('WAVファイル名を指定してください。'); end
    if nargin < 2 || isempty(segmap_csv), error('segmap CSV を指定してください。'); end
    if nargin < 3 || isempty(offset_s)
        offset_s = 0;
        warning('offset_s 未指定 → 0 を使用。録音開始とスクリプト t=0 の時刻差を必ず設定すること。');
    end
    base = char(strrep(string(wav_file), '.wav', ''));

    %% === segmap から区間中央のWAV時刻を計算 ===========================
    S = readtable(segmap_csv);
    seg_name = string(S.name);
    seg_mode = string(S.mode);
    tc_script = (S.t_start + S.t_end) / 2;     % スクリプト上の区間中央[s]
    tc_wav    = tc_script + offset_s;          % WAV上の中央[s]
    nseg = numel(seg_name);

    %% === WAV情報・窓（hilbert_20260604 と同一定数）====================
    info = audioinfo(wav_file);
    fs = info.SampleRate;
    fprintf('WAV: %s | fs=%d Hz | ch=%d | %.1f s (%d samples)\n', ...
        wav_file, fs, info.NumChannels, info.Duration, info.TotalSamples);
    fprintf('segmap: %s | offset=%.1f s | 区間数 %d\n', segmap_csv, offset_s, nseg);
    if fs ~= 192000
        warning('SampleRate が 192000 ではありません（%d）。解析定数を確認すること。', fs);
    end

    win_pre = 10000;            % 先頭オフセット[サンプル]
    win_len = fs*10 + 20000;    % 解析窓 ≒10.1 s（偶数）
    crop    = 100000;           % 端クロップ[サンプル]

    %% === 結果格納 ======================================================
    R = struct('name',{}, 'tc_s',{}, 'std_s',{}, 'fc_Hz',{}, ...
               'lf_peak_pow',{}, 'lf_peak_freq',{});
    P_all = cell(1, nseg);  f_all = cell(1, nseg);

    %% === 区間ループ ====================================================
    for is = 1:nseg
        name = seg_name(is);
        s0 = win_pre + round(tc_wav(is)*fs) + 1;
        s1 = s0 + win_len - 1;
        if s0 < 1 || s1 > info.TotalSamples
            warning('区間 %s（WAV中央 %.1fs）は録音範囲外 → スキップ（[%d %d] / 総%d）。', ...
                name, tc_wav(is), s0, s1, info.TotalSamples);
            continue;
        end

        amoto2 = audioread(wav_file, [s0 s1]);
        Nseg = size(amoto2, 1);

        % --- 各chをヒルベルト変換 → ジッタ抽出（hilbert_20260604 と同一）---
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

            jitter = (angle2 - Y2) / (2*pi*48000);
            j(:, ch) = bwlimit3(jitter, 0, 12000, fs);
        end

        % --- ch間差・指標 ---
        sa  = j(:,1) - j(:,2);
        sa2 = sa((crop+1):(end-crop));
        P   = abs(fft(sa2)).^2;
        Nf  = numel(sa2);
        freqs = (0:Nf-1)' * fs / Nf;

        lf = (freqs >= 0.2) & (freqs <= 2);          % 低周波ハンチング帯
        [lf_pow, ki] = max(P .* lf);
        lf_freq = freqs(ki);
        s_std = std(sa2);

        R(end+1) = struct('name',name, 'tc_s',tc_wav(is), 'std_s',s_std, ...
            'fc_Hz',mean(fc), 'lf_peak_pow',lf_pow, 'lf_peak_freq',lf_freq); %#ok<AGROW>
        P_all{is} = P;  f_all{is} = freqs;

        fprintf('[%-6s %-5s] std=%.4g s | LFpeak=%.3g @ %.2f Hz | fc=%.1f Hz\n', ...
            name, seg_mode(is), s_std, lf_pow, lf_freq, mean(fc));

        % --- 図1: スペクトル ---
        f1 = figure('Name',name+" spectrum",'NumberTitle','off','Visible','off');
        plot(freqs, P); set(gca,'yscale','log','xscale','log'); grid on;
        xlabel('freq [Hz]'); ylabel('power');
        title(sprintf('%s [%s]  std=%.3g s', name, seg_mode(is), s_std), 'Interpreter','none');
        exportgraphics(f1, sprintf('%s_%s_spectrum.png', base, name), 'Resolution', 300);
        close(f1);

        % --- 図2: ジッタ時間波形 ---
        f2 = figure('Name',name+" jitter",'NumberTitle','off','Visible','off');
        plot(sa2, '.'); grid on;
        xlabel('sample'); ylabel('jitter diff [s]');
        title(sprintf('%s [%s]  std=%.3g s', name, seg_mode(is), s_std), 'Interpreter','none');
        exportgraphics(f2, sprintf('%s_%s_jitter.png', base, name), 'Resolution', 300);
        close(f2);
    end

    if isempty(R)
        warning('解析できた区間がありません。offset_s と WAV長 / segmap を確認。');
        return;
    end

    %% === サマリ表示 + CSV =============================================
    fprintf('\n===== 区間別ジッタ summary =====\n');
    fprintf('%-7s %8s %12s %12s\n', 'seg','tc_s','std[s]','LFpk@Hz');
    for r = 1:numel(R)
        fprintf('%-7s %8.1f %12.4g %6.3g@%.2f\n', ...
            R(r).name, R(r).tc_s, R(r).std_s, R(r).lf_peak_pow, R(r).lf_peak_freq);
    end
    [~, ibest] = min([R.std_s]);
    fprintf('\n>>> ジッタ最小（勝ち筋）: %s  std=%.4g s\n', R(ibest).name, R(ibest).std_s);

    Tn  = string({R.name})';
    Tbl = table(Tn, [R.tc_s]', [R.std_s]', [R.fc_Hz]', [R.lf_peak_pow]', [R.lf_peak_freq]', ...
        'VariableNames', {'segment','tc_s','std_s','fc_Hz','lf_peak_pow','lf_peak_freq'});
    sum_csv = sprintf('%s_jitter_summary.csv', base);
    writetable(Tbl, sum_csv);
    fprintf('summary: %s\n', sum_csv);

    %% === 比較図: スペクトル重ね描き ===================================
    fc1 = figure('Name','compare spectrum','NumberTitle','off','Visible','off');
    hold on; leg = strings(0,1);
    for is = 1:nseg
        if ~isempty(P_all{is})
            plot(f_all{is}, P_all{is});
            leg(end+1,1) = seg_name(is); %#ok<AGROW>
        end
    end
    set(gca,'yscale','log','xscale','log'); grid on;
    xlabel('freq [Hz]'); ylabel('power'); legend(leg, 'Location','southwest', 'Interpreter','none');
    title('区間別ジッタ差スペクトル比較（左側＝低周波ハンチング）');
    exportgraphics(fc1, sprintf('%s_compare_spectrum.png', base), 'Resolution', 300);
    close(fc1);

    %% === 比較図: std 棒グラフ =========================================
    fc2 = figure('Name','compare std','NumberTitle','off','Visible','off');
    bar([R.std_s]); grid on;
    set(gca, 'XTickLabel', {R.name}, 'TickLabelInterpreter','none');
    ylabel('std of jitter diff [s]');
    title('区間別ジッタ差 std（小さいほど良い・HOLDが基準）');
    ih = find(strcmpi({R.name},'HOLD'), 1);
    if ~isempty(ih)
        yline(R(ih).std_s, 'r--', 'HOLD');
    end
    exportgraphics(fc2, sprintf('%s_compare_std.png', base), 'Resolution', 300);
    close(fc2);

    fprintf('比較図: %s_compare_spectrum.png / %s_compare_std.png\n完了。\n', base, base);
end
