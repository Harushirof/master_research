function realtime_df_filter
%---------------------------------------------------------------
% 10 MHz OCXO×2 の周波数差をリアルタイム取得し，
% Z-score 外れ値除去＋可変 IIR でノイズを低減。
% 計測を Ctrl+C で止めると σ を計算して結果を描画。
%---------------------------------------------------------------

%% ■ パラメータ調整
Ts        = 0.05;   % サンプリング周期 0.05 s (=20 Hz)
M         = 40;     % σ 計算ウインドウ幅
z_th      = 3;      % Z-score 閾値
alpha_min = 0.05;   % IIR 最小重み
alpha_max = 0.40;   % IIR 最大重み
sigma_ref = 100;    % σ=100 Hz で α = 0.40
buf       = nan(1,M);
idx       = 1;

%% ■ 計測器接続
ip  = "192.168.1.61";
dev = visadev("TCPIP0::"+ip+"::inst0::INSTR");
dev.Timeout = 10;
writeline(dev,":RUN");

% （必要なら）測定スロット設定
writeline(dev,":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev,":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

fprintf("===  Δf 計測開始  — Ctrl+C で停止 ===\n");

%% ■ 描画セットアップ
figure('Name','Δf raw vs filtered');
tiledlayout(2,1,'Padding','compact');
ax1 = nexttile; title(ax1,'Real-time trace'); hold(ax1,'on'); grid(ax1,'on');
l_raw  = animatedline(ax1,'DisplayName','raw');
l_filt = animatedline(ax1,'DisplayName','filtered'); legend(ax1,'show');
ax2 = nexttile; title(ax2,'Rolling σ'); grid(ax2,'on');
l_sig  = animatedline(ax2);

%% ■ メインループ
rawLog  = [];
filtLog = [];
sigLog  = [];
tic
while true          % ← Ctrl+C でここを割り込む
    %% 1) Δf 読み取り
    df = readDeltaF(dev);          % 下の helper 参照

    %% 2) Z-score 外れ値除去
    buf(idx) = df;  idx = mod(idx,M)+1;
    mu  = mean(buf,'omitnan');     % 平均
    sig = std(buf,'omitnan');      % σ
    if ~isnan(sig) && abs(df-mu) > z_th*sig
        df_clean = mu;             % 外れ値→平均で置換
    else
        df_clean = df;
    end

    %% 3) 可変 IIR
    if ~isnan(sig) && sig>0
        alpha = min(alpha_max, max(alpha_min, sigma_ref/sig));
    else
        alpha = alpha_min;
    end
    if isempty(filtLog)
        y = df_clean;              % 初回のみ直値
    else
        y = alpha*df_clean + (1-alpha)*filtLog(end);
    end

    %% 4) ログ・描画
    tnow = toc;
    addpoints(l_raw, tnow, df);
    addpoints(l_filt,tnow, y);
    addpoints(l_sig, tnow, sig);
    drawnow limitrate;

    rawLog(end+1)  = df;
    filtLog(end+1) = y;
    sigLog(end+1)  = sig;

    pause(Ts);
end

%% ===== Ctrl+C で停止するとここより下は実行されない =====
end  % ── realtime_df_filter ここで終了 ──


%===== Δf を一回読むだけのヘルパ関数 =====
function df = readDeltaF(dev)
    writeline(dev,":MEAS:ADV:P1:VAL?");  f1 = str2double(readline(dev));
    writeline(dev,":MEAS:ADV:P2:VAL?");  f2 = str2double(readline(dev));
    df = f1 - f2;
end

