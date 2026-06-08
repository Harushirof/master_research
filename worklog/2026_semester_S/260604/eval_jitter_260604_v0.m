function m = eval_jitter_260604_v0(wav_file, win_start_s, win_len_s, fs, do_plot)
%====================================================================
% 録音(WAV)の指定区間のチャンネル間ジッタ差を評価する。
% hilbert.m / bwlimit3.m のロジックを関数化し、パターン比較用の
% 数値指標（std と低周波ピーク高さ）を返す。
%
% 使い方の想定:
%   同一 run 内で FB 区間と HOLD 区間を別々に評価し、
%   FB を HOLD に近づけられたかをパターン間で比較する。
%
%   % 例: FB 区間（録音先頭から 30〜290 s）と HOLD 区間（330〜590 s）
%   mFB   = eval_jitter_260604_v0("260604_xxxx.wav",  30, 260, 192000, true);
%   mHOLD = eval_jitter_260604_v0("260604_xxxx.wav", 330, 260, 192000, true);
%   fprintf('FB std=%.3g, HOLD std=%.3g\n', mFB.std_s, mHOLD.std_s);
%
% 入力:
%   wav_file    : WAV ファイル名（2ch）
%   win_start_s : 解析開始時刻 [s]（録音先頭基準。制御 t=0 ではない点に注意）
%   win_len_s   : 解析窓長 [s]
%   fs          : サンプリング周波数 [Hz]（DR-100MK3 なら 192000）
%   do_plot     : true で時間波形＋スペクトルを表示・保存（省略時 false）
%
% 出力 m:
%   .std_s          : ジッタ差 sa の標準偏差 [s]（小さいほど良い）
%   .peak_lf_pow    : 低周波(0.2〜2 Hz)スペクトルピーク高さ（ハンチング指標）
%   .peak_lf_freq   : そのピーク周波数 [Hz]
%   .fc             : ヒルベルトで同定した中心周波数 [Hz]（ch平均）
%   .sa             : ジッタ差時系列 [s]（クロップ後）
%====================================================================

    if nargin < 4 || isempty(fs),      fs = 192000;  end
    if nargin < 5 || isempty(do_plot), do_plot = false; end

    amoto = audioread(wav_file);
    Nall  = size(amoto, 1);

    start_idx = round(win_start_s * fs) + 1;
    end_idx   = start_idx + round(win_len_s * fs) - 1;
    if start_idx < 1 || end_idx > Nall
        error('指定窓が録音範囲外です（録音長 %.1f s, 要求 %.1f〜%.1f s）。', ...
            Nall / fs, win_start_s, win_start_s + win_len_s);
    end
    amoto2 = amoto(start_idx:end_idx, :);

    %% === 各チャンネルをヒルベルト変換 → ジッタ抽出 ===================
    Nseg = size(amoto2, 1);
    j  = zeros(Nseg, 2);
    fc = zeros(1, 2);
    for ch = 1:2
        aw = amoto2(:, ch);

        % ヒルベルト変換（FFTで負周波数を反転）
        N  = numel(aw);
        a2 = fft(aw);
        a2((N/2+2):N) = -a2((N/2+2):N);
        a3 = imag(ifft(a2));
        angle1 = angle(aw + 1i * a3);
        angle2 = unwrap(angle1);

        % 線形フィッティング（ax+b）で中心周波数と直線位相を求める
        Y  = angle2;
        X  = (1:numel(Y))';
        N2 = numel(X);
        A  = [sum(X.^2) sum(X); sum(X) N2];
        keisuu = A \ [sum(X.*Y); sum(Y)];
        Y2 = X * keisuu(1) + keisuu(2);

        fc(ch) = keisuu(1) * fs / (2*pi);   % 中心周波数 [Hz]

        % ジッタ（直線位相からの残差を時間換算）→ 0〜12kHz に帯域制限
        jitter = (Y - Y2) / (2*pi*48000);
        j(:, ch) = bwlimit3(jitter, 0, 12000, fs);
    end

    %% === チャンネル間差・指標 =========================================
    sa = j(:,1) - j(:,2);
    crop = min(100000, floor(Nseg/4));      % 端の過渡をクロップ
    sa2  = sa((crop+1):(end-crop));

    P = abs(fft(sa2)).^2;
    Nfft = numel(sa2);
    freqs = (0:Nfft-1)' * fs / Nfft;

    % 低周波(0.2〜2 Hz)ピーク = ハンチング指標
    lf = (freqs >= 0.2) & (freqs <= 2);
    [peak_lf_pow, k] = max(P .* lf);
    lf_idx = find(lf);
    peak_lf_freq = NaN;
    if ~isempty(lf_idx)
        peak_lf_freq = freqs(k);
    end

    m = struct();
    m.std_s        = std(sa2);
    m.peak_lf_pow  = peak_lf_pow;
    m.peak_lf_freq = peak_lf_freq;
    m.fc           = mean(fc);
    m.sa           = sa2;

    fprintf('[eval] win %.0f-%.0f s | std=%.3g s | LF peak %.3g @ %.2f Hz | fc=%.1f Hz\n', ...
        win_start_s, win_start_s + win_len_s, m.std_s, m.peak_lf_pow, m.peak_lf_freq, m.fc);

    %% === プロット =====================================================
    if do_plot
        f1 = figure('Name', 'jitter diff (time)', 'NumberTitle', 'off');
        plot(sa2, '.'); grid on;
        xlabel('sample'); ylabel('jitter diff [s]');
        title(sprintf('win %.0f-%.0f s  std=%.3g s', ...
            win_start_s, win_start_s + win_len_s, m.std_s));

        f2 = figure('Name', 'jitter diff (spectrum)', 'NumberTitle', 'off');
        plot(freqs, P); set(gca, 'yscale', 'log', 'xscale', 'log'); grid on;
        xlabel('freq [Hz]'); ylabel('power');
        title('jitter diff spectrum');
    end
end
