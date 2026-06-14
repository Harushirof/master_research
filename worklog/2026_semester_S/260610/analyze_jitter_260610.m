function R = analyze_jitter_260610(wav_file, segmap_csv, offset_s, tag, f0)
%====================================================================
% 260610 録音(WAV)の区間別ジッタ解析 → **位相雑音 dBc/Hz** で作図
%
%   hilbert + bwlimit3（260604/260608と同一ロジック）で各区間中央約10sの
%   2ch間ジッタ差 sa(t)=x1-x2 [s] を抽出し、片側PSD→位相雑音 L(f) [dBc/Hz]
%   に変換して作図する。区間中央時刻は segmap.csv から自動計算。
%
%   位相雑音の換算（搬送波 f0 基準, 2台差=相対位相雑音）:
%     Sx(f)  = 片側PSD of sa   [s^2/Hz]   （Hann窓, 正規化済み）
%     Sφ(f)  = (2π f0)^2 · Sx(f)          [rad^2/Hz]
%     L(f)   = 10·log10(Sφ(f)/2)          [dBc/Hz]
%   ※ f0 は発振器の搬送波（既定 10 MHz）。値は f0 で素直にスケールする。
%   ※ 2台差なので「相対位相雑音」。無相関で等価なら単体は約3dB下。
%
%   入力:
%     wav_file    その方式の録音WAV
%     segmap_csv  その実験の *_segmap.csv
%     offset_s    スクリプトt=0 が WAV 上で何秒か（録音開始→t=0 の秒数）
%     tag         出力名の接頭辞（例 "pid" / "model"）。省略時はWAV名。
%     f0          搬送波周波数 [Hz]（既定 10e6）
%
%   自動保存（dBc/Hz のみ）:
%     <tag>_<seg>_PN.png        … 区間別 位相雑音 L(f) [dBc/Hz]
%     <tag>_jitter_summary.csv  … std[s] / 0.2-2Hz帯ピーク[dBc/Hz] 一覧
%
%   返り値 R（compare_jitter_260610 用に L(f) を保持）:
%     R.tag, R.f0, R.specs(name,mode,std_s,lf_peak_dbc,lf_peak_freq,f,Lf)
%
%   使い方（Current Folder を 260610 に）:
%     Rp = analyze_jitter_260610("rec_pid.wav",   "frfr_pid_lowgain_*_segmap.csv", 10, "pid");
%     Rm = analyze_jitter_260610("rec_model.wav", "frfr_model_*_segmap.csv",       12, "model");
%     compare_jitter_260610(Rp, Rm);
%====================================================================
    if nargin < 1 || isempty(wav_file),   error('WAVファイル名を指定してください。'); end
    if nargin < 2 || isempty(segmap_csv), error('segmap CSV を指定してください。'); end
    if nargin < 3 || isempty(offset_s)
        offset_s = 0;
        warning('offset_s 未指定 → 0。録音開始とスクリプトt=0 の時刻差を必ず設定すること。');
    end
    if nargin < 4 || isempty(tag), tag = char(strrep(string(wav_file),'.wav','')); end
    if nargin < 5 || isempty(f0), f0 = 10e6; end      % 搬送波 [Hz]
    tag = char(tag);

    %% === segmap → 区間中央のWAV時刻 ===================================
    S = readtable(segmap_csv);
    seg_name = string(S.name);
    seg_mode = string(S.mode);
    tc_wav = (S.t_start + S.t_end)/2 + offset_s;
    nseg = numel(seg_name);

    %% === WAV情報・窓（260604/260608 と同一定数）======================
    info = audioinfo(wav_file);
    fs = info.SampleRate;
    fprintf('[%s] WAV:%s fs=%d ch=%d %.1fs | segmap:%s offset=%.1fs | f0=%.3g Hz | %d区間\n', ...
        tag, wav_file, fs, info.NumChannels, info.Duration, segmap_csv, offset_s, f0, nseg);
    if fs ~= 192000
        warning('SampleRate が 192000 ではありません（%d）。解析定数を確認すること。', fs);
    end
    win_pre = 10000;  win_len = fs*10 + 20000;  crop = 100000;

    %% === 区間ループ ====================================================
    specs = struct('name',{}, 'mode',{}, 'std_s',{}, 'lf_peak_dbc',{}, ...
                   'lf_peak_freq',{}, 'fc_Hz',{}, 'f',{}, 'Lf',{});
    for is = 1:nseg
        name = seg_name(is);
        s0 = win_pre + round(tc_wav(is)*fs) + 1;
        s1 = s0 + win_len - 1;
        if s0 < 1 || s1 > info.TotalSamples
            warning('区間 %s（WAV中央 %.1fs）は録音範囲外 → スキップ。', name, tc_wav(is));
            continue;
        end
        amoto2 = audioread(wav_file, [s0 s1]);
        Nseg = size(amoto2, 1);

        % --- 各chをヒルベルト変換 → ジッタ抽出（既存と同一）---
        j = zeros(Nseg, 2);  fc = zeros(1, 2);
        for ch = 1:2
            aw = amoto2(:, ch);  N = numel(aw);
            a2 = fft(aw);  a2((N/2+2):N) = -a2((N/2+2):N);
            a3 = imag(ifft(a2));
            angle2 = unwrap(angle(aw + 1i*a3));
            X = (1:numel(angle2))';
            A = [sum(X.^2) sum(X); sum(X) numel(X)];
            k = A \ [sum(X.*angle2); sum(angle2)];
            Y2 = X*k(1) + k(2);
            fc(ch) = k(1)*fs/(2*pi);
            jitter = (angle2 - Y2) / (2*pi*48000);     % 時間ジッタ [s]
            j(:, ch) = bwlimit3(jitter, 0, 12000, fs);
        end

        % --- ch間差 [s] → 位相雑音 L(f) [dBc/Hz] ---
        sa  = j(:,1) - j(:,2);
        sa2 = sa((crop+1):(end-crop));
        s_std = std(sa2);

        Nn  = numel(sa2);
        w   = 0.5 - 0.5*cos(2*pi*(0:Nn-1)'/(Nn-1));   % Hann窓（Toolbox非依存）
        U   = sum(w.^2);
        Xf  = fft(sa2 .* w);
        Sx2 = (abs(Xf).^2) / (fs * U);                % 両側PSD [s^2/Hz]
        Nh  = floor(Nn/2);
        f   = (0:Nh)' * fs / Nn;
        Sx  = Sx2(1:Nh+1);
        Sx(2:end-1) = 2*Sx(2:end-1);                  % 片側化
        Sphi = (2*pi*f0)^2 * Sx;                       % [rad^2/Hz]
        Lf   = 10*log10(Sphi/2);                       % [dBc/Hz]
        % f=0 は対数軸で扱えないので除外
        f = f(2:end);  Lf = Lf(2:end);

        lf = (f >= 0.2) & (f <= 2);                    % 低周波ハンチング帯
        [lf_pk, ki] = max(Lf(lf));
        f_lf = f(lf);  lf_freq = f_lf(ki);

        specs(end+1) = struct('name',name, 'mode',seg_mode(is), 'std_s',s_std, ...
            'lf_peak_dbc',lf_pk, 'lf_peak_freq',lf_freq, 'fc_Hz',mean(fc), ...
            'f',f, 'Lf',Lf); %#ok<AGROW>

        fprintf('  [%-8s %-5s] std=%.4g s | LFpeak=%.1f dBc/Hz @ %.2f Hz | fc=%.1f Hz\n', ...
            name, seg_mode(is), s_std, lf_pk, lf_freq, mean(fc));

        % --- 図1: 位相雑音 L(f) [dBc/Hz] ---
        f1 = figure('Name',name+" PN",'NumberTitle','off','Visible','off','Position',[80 80 760 480]);
        semilogx(f, Lf, '-'); grid on;
        xlim([0.05 max(f)]);
        xlabel('offset frequency [Hz]'); ylabel('L(f) [dBc/Hz]');
        title(sprintf('[%s] %s [%s]  位相雑音 (f0=%.0f MHz, 2台差)  std=%.3g s', ...
            tag, name, seg_mode(is), f0/1e6, s_std), 'Interpreter','none');
        xline(0.6, 'k:', '0.6Hz', 'HandleVisibility','off');
        exportgraphics(f1, sprintf('%s_%s_PN.png', tag, name), 'Resolution', 300);
        close(f1);

        % --- 図2: ジッタ差 時間波形 [ps] ---
        f2 = figure('Name',name+" jitter",'NumberTitle','off','Visible','off','Position',[100 100 760 420]);
        tjit = (0:numel(sa2)-1)'/fs;                 % 時間軸 [s]
        plot(tjit, sa2*1e12, '.'); grid on;          % ps表示
        xlabel('time [s]'); ylabel('jitter diff [ps]');
        title(sprintf('[%s] %s [%s]  ジッタ差 std=%.3g ps', ...
            tag, name, seg_mode(is), s_std*1e12), 'Interpreter','none');
        exportgraphics(f2, sprintf('%s_%s_jitter.png', tag, name), 'Resolution', 300);
        close(f2);
    end

    if isempty(specs)
        warning('[%s] 解析できた区間がありません。offset_s と WAV長 / segmap を確認。', tag);
        R = struct('tag',tag, 'f0',f0, 'specs',specs);  return;
    end

    %% === サマリ CSV ===================================================
    Tbl = table(string({specs.name})', string({specs.mode})', [specs.std_s]', ...
        [specs.lf_peak_dbc]', [specs.lf_peak_freq]', [specs.fc_Hz]', ...
        'VariableNames', {'segment','mode','std_s','lf_peak_dBcHz','lf_peak_freq','fc_Hz'});
    sum_csv = sprintf('%s_jitter_summary.csv', tag);
    writetable(Tbl, sum_csv);
    [~, ib] = min([specs.lf_peak_dbc]);
    fprintf('[%s] >>> 低周波(0.2-2Hz)最小: %s %.1f dBc/Hz | summary: %s\n', ...
        tag, specs(ib).name, specs(ib).lf_peak_dbc, sum_csv);

    R = struct('tag',tag, 'f0',f0, 'specs',specs);
end
