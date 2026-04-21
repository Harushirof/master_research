function ocxo_df_filter_run
%======================================================================
%  10 MHz OCXO ×2 の周波数差 Δf をリアルタイム取得し，
%  Z-score 外れ値除去＋可変 IIR でノイズを低減するスクリプト
%  ゲート時間 0.1 s でオシロ側平均も併用。
%  Ctrl+C で計測停止 → σ の比較とヒストグラムを表示。
%======================================================================

%% ■ ユーザ設定パラメータ
ip        = "192.168.1.61";   % オシロの IP アドレス
Ts        = 0.05;             % サンプリング周期 [s]（≈20 Hz）
M         = 200;              % rolling σ 用ウインドウ幅（点）≈10 s
z_th      = 3;                % Z-score 閾値
alpha_min = 0.01;             % 可変 IIR の最小重み
alpha_max = 0.40;             % 可変 IIR の最大重み
sigma_ref = 500;              % σ=500 Hz を基準に α をスケール

%% ■ 計測器接続 & 初期化
dev = visadev("TCPIP0::"+ip+"::inst0::INSTR");
dev.Timeout = 15;
writeline(dev,":RUN");                        % 取り込み開始

% 測定スロットを設定（既に設定済みなら省略可）
writeline(dev,":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev,":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

% ゲート時間を 0.1 s に延長して平均効果を高める
writeline(dev,":MEAS:ADV:P1:GATE:TIME 0.1");
writeline(dev,":MEAS:ADV:P2:GATE:TIME 0.1");

fprintf("=== Δf 計測開始  (Ctrl+C で停止) ===\n");

%% ■ 描画準備
figure('Name','OCXO Δf monitor');
tiledlayout(2,1,'Padding','compact');

ax1 = nexttile(1);
title(ax1,'Δf  Raw vs Filtered'); hold(ax1,'on'); grid(ax1,'on');
l_raw = animatedline(ax1,'DisplayName','raw');
l_flt = animatedline(ax1,'DisplayName','filtered');
legend(ax1,'show');

ax2 = nexttile(2);
title(ax2,'Rolling σ'); grid(ax2,'on');
l_sig = animatedline(ax2);

%% ■ ループ用変数
buf     = nan(1,M); idx = 1;
rawLog  = [];       fltLog = [];    sigLog = [];

tic;  % 時間計測開始
try
    while true
        %% 1) Δf を 1 回読み取り（ゲート平均値）
        df = readDeltaF(dev);

        %% 2) Z-score で外れ値判定・除去
        buf(idx) = df;  idx = mod(idx,M)+1;
        mu  = mean(buf,'omitnan');
        sig = std(buf,'omitnan');

        if ~isnan(sig) && abs(df - mu) > z_th * sig
            df_clean = mu;              % 外れ値なら平均に置換
        else
            df_clean = df;
        end

        %% 3) 可変 IIR フィルタ
        if ~isnan(sig) && sig > 0
            alpha = min(alpha_max, max(alpha_min, sigma_ref / sig));
        else
            alpha = alpha_min;          % 初期や σ=0 対策
        end

        if isempty(fltLog)
            y = df_clean;               % 初回はそのまま
        else
            y = alpha * df_clean + (1 - alpha) * fltLog(end);
        end

        %% 4) ログ・プロット更新
        tnow = toc;
        addpoints(l_raw, tnow, df);
        addpoints(l_flt, tnow, y);
        addpoints(l_sig, tnow, sig);
        drawnow limitrate;

        rawLog(end+1)  = df;
        fltLog(end+1)  = y;
        sigLog(end+1)  = sig;

        pause(Ts);
    end

catch ME  % Ctrl+C で割り込んだ場合もここへ
    fprintf("\n=== 計測停止 (%s) ===\n", ME.identifier);
end

%% ■ 結果まとめ表示
sigma_raw = std(rawLog,'omitnan');
sigma_flt = std(fltLog,'omitnan');
fprintf(" σ(raw)      = %.1f Hz\n σ(filtered) = %.1f Hz   → %.1f × 低減\n", ...
        sigma_raw, sigma_flt, sigma_raw / sigma_flt);

figure('Name','Histogram: Δf before / after');
edges = linspace(min(rawLog), max(rawLog), 120);
histogram(rawLog, edges, 'Normalization','pdf', 'DisplayName','raw'); hold on
histogram(fltLog, edges, 'Normalization','pdf', 'DisplayName','filtered');
legend; title('Δf distribution before / after');

end  % ===== ocxo_df_filter_run 終了 =====


%----------------------------------------------------------------------
%  Δf を 1 回取得するヘルパ関数
%----------------------------------------------------------------------
function df = readDeltaF(dev)
    writeline(dev,":MEAS:ADV:P1:VAL?");
    f1 = str2double(readline(dev));
    writeline(dev,":MEAS:ADV:P2:VAL?");
    f2 = str2double(readline(dev));
    df = f1 - f2;
end

