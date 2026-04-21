function ocxo_df_filter_view
%===============================================================
%  ・raw / filtered の両方について rolling σ を表示
%  ・alpha のスケーリングを調整し過度な平滑化を防止
%===============================================================
%% パラメータ
ip         = "192.168.1.61";
Ts         = 0.05;
M          = 200;
z_th       = 3;
alpha_min  = 0.03;     % ← 応答速度確保
alpha_max  = 0.40;
sigma_ref  = 3000;     % ← α が張り付かない範囲に拡大

%% 接続 & スロット設定（省略可ならコメントアウト）
dev = visadev("TCPIP0::"+ip+"::inst0::INSTR");  dev.Timeout = 15;
writeline(dev,":RUN");
writeline(dev,":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev,":MEAS:ADV:P2:TYPE FREQuency,CHAN2");
writeline(dev,":MEAS:ADV:P1:GATE:TIME 0.1");    % 効いているか要確認
writeline(dev,":MEAS:ADV:P2:GATE:TIME 0.1");

%% 描画セットアップ
figure('Name','Δf monitor'); tiledlayout(3,1,'Padding','compact');
ax1 = nexttile; title(ax1,'Δf  Raw vs Filtered'); grid(ax1,'on'); hold(ax1,'on');
l_raw = animatedline(ax1); l_flt = animatedline(ax1,'Color',[0.85 0 0]);
ax2 = nexttile; title(ax2,'Rolling σ  (raw)');  grid(ax2,'on'); l_sig_r = animatedline(ax2);
ax3 = nexttile; title(ax3,'Rolling σ  (filtered)'); grid(ax3,'on'); l_sig_f = animatedline(ax3);

%% バッファ
buf_r = nan(1,M); buf_f = nan(1,M); idx = 1;
rawLog=[]; fltLog=[];

tic
try
    while true
        %% ── Δf 取得
        df = readDeltaF(dev);

        %% ── 外れ値除去
        buf_r(idx) = df;  mu = mean(buf_r,'omitnan');  sig_r = std(buf_r,'omitnan');
        if ~isnan(sig_r) && abs(df-mu) > z_th*sig_r
            df_use = mu;
        else
            df_use = df;
        end

        %% ── 可変 IIR
        if ~isnan(sig_r) && sig_r>0
            alpha = min(alpha_max, max(alpha_min, sigma_ref/sig_r));
        else
            alpha = alpha_min;
        end
        if isempty(fltLog)
            y = df_use;
        else
            y = alpha*df_use + (1-alpha)*fltLog(end);
        end

        %% ── rolling σ (filtered) 計算
        buf_f(idx) = y;  sig_f = std(buf_f,'omitnan');
        idx = mod(idx,M)+1;

        %% ── 描画
        t = toc;
        addpoints(l_raw,t,df); addpoints(l_flt,t,y);
        addpoints(l_sig_r,t,sig_r); addpoints(l_sig_f,t,sig_f);
        drawnow limitrate;

        rawLog(end+1)=df; fltLog(end+1)=y;
        pause(Ts);
    end
catch
    disp('--- STOP ---');
end

fprintf('σ(raw)= %.1f Hz,   σ(filtered)= %.1f Hz\n', ...
        std(rawLog), std(fltLog));
end

function df = readDeltaF(dev)
    writeline(dev,":MEAS:ADV:P1:VAL?"); f1=str2double(readline(dev));
    writeline(dev,":MEAS:ADV:P2:VAL?"); f2=str2double(readline(dev));
    df = f1 - f2;
end
