% 2025/10/10とおなじもの（1,2の修正を反映）
function frfr_fb_1010_v10()
    %% --- 初期設定 -------------------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev));

    %% --- パラメータ -----------------------------------------------------
    fb_interval = 0.3;              % [s] フィードバック周期
    total_time  = 180;              % [s] 実行時間
    target      = 50;               % [ns] 目標FRFR
    Kp          = 0.0001;           % 比例ゲイン
    frfr_threshold = 0.5;           % [ns] |error|<閾値のとき保持（※errorベースに変更）

    JUMP_DETECT_NS = 50;           % [ns] ラップ検出閾値
    OFFSET_STEP_NS = 100;          % [ns] 補正幅（累積）

    ao0_const   = 1.54;            % [V] ao0固定出力
    v_ao1       = 1.54;            % [V] ao1初期値
    min_voltage = 0.0; 
    max_voltage = 5.0; 
    min_step    = 0.001;

    stable_duration        = 10;   % [s] 安定判定窓長
    stable_delta_threshold = 0.5;  % [ns] 安定判定用Δ閾値

    %% --- 状態変数 ------------------------------------------------------
    prev_frfr = NaN;
    frfr_offset = 0;               % 累積補正
    last_stable_time = NaN;

    %% --- ログ -----------------------------------------------------------
    time_log = []; ao1_log = []; frfr_log = [];

    %% --- グラフ（上：FRFR, 下：ao1電圧） ------------------------------
    figure('Name','FRFR Feedback Monitor','NumberTitle','off');
    tl = tiledlayout(2,1,'TileSpacing','compact');

    ax1 = nexttile(1);
    h_frfr = plot(ax1, NaN, NaN, 'r-'); grid on;
    ylabel(ax1,'Corrected FRFR [ns]');
    title(ax1,'Corrected FRFR Over Time');

    ax2 = nexttile(2);
    h_ao1 = plot(ax2, NaN, NaN, 'b-'); grid on;
    ylabel(ax2,'Voltage on ao1 [V]');
    xlabel(ax2,'Time [s]');
    title(ax2,'ao1 Voltage (FB Channel) Over Time');

    linkaxes([ax1, ax2], 'x');

    %% --- 初期出力 ------------------------------------------------------
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("開始: ao0=%.3f V(固定), ao1=%.3f V(初期)\n", ao0_const, v_ao1);

    %% --- 計測開始 ------------------------------------------------------
    t_start = datetime('now');
    stable_buffer = [];

    %% --- メインループ --------------------------------------------------
    while true
        t = seconds(datetime('now') - t_start); % 経過秒
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            %% --- 測定 --- 
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            raw_frfr = frfr_sec * 1e9; % [ns]

            %% --- FRFR補正（±200累積型） -------------------------------
            if isnan(prev_frfr)
                delta_raw = NaN;
            else
                delta_raw = raw_frfr - prev_frfr;

                if delta_raw <= -JUMP_DETECT_NS
                    frfr_offset = frfr_offset + OFFSET_STEP_NS;
                    fprintf("ラップダウン検出: Δ=%.1f ns → offset += +%d → %.1f\n", ...
                            delta_raw, OFFSET_STEP_NS, frfr_offset);
                elseif delta_raw >= +JUMP_DETECT_NS
                    frfr_offset = frfr_offset - OFFSET_STEP_NS;
                    fprintf("ラップアップ検出: Δ=%.1f ns → offset += -%d → %.1f\n", ...
                            delta_raw, OFFSET_STEP_NS, frfr_offset);
                end
            end

            % 修正後FRFRを計算
            frfr_corrected = raw_frfr + frfr_offset;
            prev_frfr = raw_frfr;

            %% --- 安定判定（raw Δで） ----------------------------------
            if ~isnan(delta_raw)
                stable_buffer = [stable_buffer, abs(delta_raw)];
                if numel(stable_buffer) > round(stable_duration / fb_interval)
                    stable_buffer(1) = [];
                end
            end
            is_stable = (numel(stable_buffer) == round(stable_duration / fb_interval)) ...
                        && (max(stable_buffer) < stable_delta_threshold);
            if is_stable && isnan(last_stable_time)
                last_stable_time = t;
                fprintf("安定検出: t=%.1f s\n", t);
            elseif ~is_stable
                last_stable_time = NaN;
            end

            %% --- FB制御（修正FRFRベース） -----------------------------
            % 誤差を先に計算（変更点①②のベース）
            error_ns = frfr_corrected - target;  % 修正FRFRに対して制御

            % ② FBのON/OFF判定を error_ns ベースに変更
            if abs(error_ns) < frfr_threshold
                % 目標に十分近いときは維持
                fprintf("t=%.1f s | FRFRcorr=%.2f ns | error=%.2f ns < %.1f → ao1=%.4f V維持 (Δraw=%.2f ns)\n", ...
                        t, frfr_corrected, error_ns, frfr_threshold, v_ao1, delta_raw);
            else
                % ① dv の最小ステップ符号を error_ns に合わせる
                dv = Kp * error_ns; 
                dv = round(dv, 4);
                if abs(dv) < min_step
                    dv = min_step * sign(error_ns);  % sign(dv) → sign(error_ns)
                end
                v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                fprintf("t=%.1f s | FRFRcorr=%.2f ns | error=%.2f | ΔV=%.4f | ao1=%.4f V (Δraw=%.2f ns)\n", ...
                        t, frfr_corrected, error_ns, dv, v_ao1, delta_raw);
            end

            %% --- ログと描画 -------------------------------------------
            time_log(end+1) = t;
            ao1_log(end+1)  = v_ao1;
            frfr_log(end+1) = frfr_corrected;

            set(h_frfr, 'XData', time_log, 'YData', frfr_log);
            set(h_ao1,  'XData', time_log, 'YData', ao1_log);

            % 常に最新30秒を表示
            if t > 30
                xlim(ax1, [t-30, t+1]);
                xlim(ax2, [t-30, t+1]);
            else
                xlim(ax1, [0, max(30, t+1)]);
                xlim(ax2, [0, max(30, t+1)]);
            end

            drawnow limitrate;
            pause(fb_interval);

        catch ME
            warning("エラー: %s", ME.message);
            break;
        end
    end

    %% --- 終了処理 ------------------------------------------------------
    outputSingleScan(s, [0, 0]); % 出力を停止
end


function cleanupDAQ(s, dev)
    try, stop(s);    end
    try, release(s); end
    try, clear dev;  end
end
