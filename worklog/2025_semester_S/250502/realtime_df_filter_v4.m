function ocxo_df_filter_v3
%======================================================================
% 10 MHz OCXO×2 Δf をリアルタイム取得
% 1) 20点 movmean で瞬間ノイズを 1/√20 ≈ 4.5 分の1 へ
% 2) Z-score 外れ値除去 + 可変 IIR
%======================================================================

%% ▼ ユーザ設定
ip         = "192.168.1.61";
Ts         = 0.05;          % 20 Hz
M          = 200;           % rolling σ 窓 (10 s)
Navg       = 20;            % movmean 窓 (1 s)
z_th       = 3;
alpha_min  = 0.03;
alpha_max  = 0.40;
sigma_ref  = 3000;

%% ▼ 計測器
dev = visadev("TCPIP0::"+ip+"::inst0::INSTR");  dev.Timeout = 15;
writeline(dev,":RUN");
writeline(dev,":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev,":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

%% ▼ 描画
figure('Name','Δf monitor'); tiledlayout(3,1,'Padding','compact')
ax1 = nexttile; title(ax1,'Δf  Raw vs Filtered'); hold(ax1,'on'); grid(ax1,'on')
l_raw = animatedline(ax1);  l_flt = animatedline(ax1,'Color',[0.85 0 0])
ax2 = nexttile; title(ax2,'Rolling σ  (raw)');      grid(ax2,'on'); l_sig_r = animatedline(ax2);
ax3 = nexttile; title(ax3,'Rolling σ  (filtered)'); grid(ax3,'on'); l_sig_f = animatedline(ax3);

%% ▼ バッファ
buf_r = nan(1,M); buf_f = nan(1,M); idx = 1;
movBuf = nan(1,Navg);                        % movmean 用リング
rawLog = []; fltLog = [];

tic
try
    while true
        %% 1) Δf 読み取り
        df_inst = readDeltaF(dev);           % 瞬間値

        %% 2) movmean で 1 s 平均
        movBuf = [movBuf(2:end) df_inst];
        df = mean(movBuf,'omitnan');         % これが “raw” として以降へ

        %% 3) Z-score 外れ値除去
        buf_r(idx) = df;  mu = mean(buf_r,'omitnan');  sig_r = std(buf_r,'omitnan');
        if ~isnan(sig_r) && abs(df-mu) > z_th*sig_r
            df_use = mu;
        else
            df_use = df;
        end

        %% 4) 可変 IIR
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

        %% 5) rolling σ(filtered)
        buf_f(idx) = y;  sig_f = std(buf_f,'omitnan');
        idx = mod(idx,M)+1;

        %% 6) プロット
        t = toc;
        addpoints(l_raw,t,df);  addpoints(l_flt,t,y);
        addpoints(l_sig_r,t,sig_r); addpoints(l_sig_f,t,sig_f);
        drawnow limitrate;

        rawLog(end+1)=df;  fltLog(end+1)=y;
        pause(Ts);
    end
catch
    disp('--- STOP ---');
end

fprintf('σ(raw)= %.1f Hz   σ(filtered)= %.1f Hz  (%.1f×低減)\n', ...
        std(rawLog,'omitnan'), std(fltLog,'omitnan'), ...
        std(rawLog,'omitnan')/std(fltLog,'omitnan'));
end
%==================== helper ====================
function df = readDeltaF(dev)
    writeline(dev,":MEAS:ADV:P1:VAL?"); f1=str2double(readline(dev));
    writeline(dev,":MEAS:ADV:P2:VAL?"); f2=str2double(readline(dev));
    df = f1 - f2;
end
