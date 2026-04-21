function ocxo_df_filter_strong
%======================================================================
%  10 MHz OCXO ×2 の周波数差 Δf をリアルタイム取得し，
%   ① 2 s movmean
%   ② 9 点メディアンフィルタ
%   ③ 可変 IIR（α を σ で自動調整）
%  の 3 段でノイズを低減する。
%  実行後 Ctrl+C で停止すると σ を比較して表示。
%======================================================================

%% ▼ ユーザ設定
ip         = "192.168.1.61";  % オシロ IP
Ts         = 0.05;            % サンプリング周期 (20 Hz)
N_mean     = 40;              % movmean 幅 (40点=2 s)
N_med      = 9;               % median 幅  (奇数)
M_sigma    = 200;             % rolling σ 用窓 (10 s)
z_th       = 3;               % Z-score 外れ値閾値
alpha_min  = 0.02;            % IIR 最小重み
alpha_max  = 0.40;            % IIR 最大重み
sigma_ref  = 6000;            % σ=6000 Hz で α≈alpha_max

%% ▼ 計測器接続
dev = visadev("TCPIP0::"+ip+"::inst0::INSTR");  dev.Timeout = 15;
writeline(dev,":RUN");
writeline(dev,":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
writeline(dev,":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

%% ▼ 描画セット
figure('Name','Δf monitor (strong filter)'); tiledlayout(3,1,'Padding','compact');
ax1 = nexttile; title(ax1,'Δf  Raw vs Filtered'); grid(ax1,'on'); hold(ax1,'on');
l_raw = animatedline(ax1,'Color',[0.1 0.1 0.1]);
l_flt = animatedline(ax1,'Color',[0.85 0 0]);
ax2 = nexttile; title(ax2,'Rolling σ  (raw)');      grid(ax2,'on'); l_sig_r = animatedline(ax2);
ax3 = nexttile; title(ax3,'Rolling σ  (filtered)'); grid(ax3,'on'); l_sig_f = animatedline(ax3);

%% ▼ バッファ
buf_r = nan(1,M_sigma);   buf_f = nan(1,M_sigma);   idx = 1;
buf_mean = nan(1,N_mean); % movmean
rawLog = [];  fltLog = [];

tic;
try
    while true
        %% 1) 瞬間 Δf 取得
        df_inst = readDeltaF(dev);

        %% 2) movmean (2 s)
        buf_mean = [buf_mean(2:end) df_inst];
        df_mean = mean(buf_mean,'omitnan');

        %% 3) median filter (9 点)
        df_med = medfilt1([buf_mean(end-N_med+1:end) nan(1,max(0,N_med-numel(buf_mean)))], ...
                          N_med,'omitnan');
        df_med = df_med(end);   % 最新値だけ使用

        %% 4) Z-score 外れ値除去（raw 用）
        buf_r(idx) = df_med;
        mu_r  = mean(buf_r,'omitnan');
        sig_r = std(buf_r,'omitnan');
        if ~isnan(sig_r) && abs(df_med - mu_r) > z_th*sig_r
            df_use = mu_r;
        else
            df_use = df_med;
        end

        %% 5) 可変 IIR
        if ~isnan(sig_r) && sig_r>0
            alpha = min(alpha_max, max(alpha_min, sigma_ref/sig_r));
        else
            alpha = alpha_min;
        end
        if isempty(fltLog)
            y = df_use;                 % 初回
        else
            y = alpha*df_use + (1-alpha)*fltLog(end);
        end

        %% 6) rolling σ(filtered)
        buf_f(idx) = y;
        sig_f = std(buf_f,'omitnan');
        idx   = mod(idx,M_sigma)+1;

        %% 7) ログ & 描画
        t = toc;
        addpoints(l_raw,t,df_med);  addpoints(l_flt,t,y);
        addpoints(l_sig_r,t,sig_r); addpoints(l_sig_f,t,sig_f);
        drawnow limitrate;

        rawLog(end+1) = df_med;
        fltLog(end+1) = y;

        pause(Ts);
    end
catch
    disp('--- STOP ---');
end

%% ▼ 結果
sigma_raw = std(rawLog,'omitnan');
sigma_flt = std(fltLog,'omitnan');
fprintf('σ(raw)= %.1f Hz   σ(filtered)= %.1f Hz   → %.1f× 低減\n', ...
        sigma_raw, sigma_flt, sigma_raw/sigma_flt);
end
%-------------- helper ---------------------------------------
function df = readDeltaF(dev)
    writeline(dev,":MEAS:ADV:P1:VAL?"); f1 = str2double(readline(dev));
    writeline(dev,":MEAS:ADV:P2:VAL?"); f2 = str2double(readline(dev));
    df = f1 - f2;
end
