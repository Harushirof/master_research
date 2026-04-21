%修正FRFRに対してFB、定期的なパルスあり

function frfr_fb_1010_v9()
    %% --- 初期設定 -------------------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定 1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB可変（初期1.54V）

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 例外終了でも必ず解放
    c = onCleanup(@()cleanupDAQ(s, dev));

    %% --- パラメータ -----------------------------------------------------
    fb_interval = 0.3;              % [s] フィードバック周期
    total_time  = 180;              % [s] 実行時間
    target      = 50;               % [ns] 目標FRFR
    Kp          = 0.0001;           % 比例ゲイン
    frfr_threshold = 0.5;           % [ns] |ΔFRFR|小のときは保持
    JUMP_DETECT_NS = 50;           % [ns] ラップ判定閾値（以上/以下で発動）
    OFFSET_STEP_NS = 100;           % [ns] 補正の累積幅

    ao0_const   = 1.54;             % [V] ao0は常時この固定値
    v_ao1       = 1.54;             % [V] ao1 初期電圧（可変）
    min_voltage = 0.0;              % [V]
    max_voltage = 5.0;              % [V]
    min_step    = 0.001;            % [V] 最小ステップ

    % 安定判定・パルス
    stable_duration        = 10;    % [s] 安定判定窓長
    stable_delta_threshold = 0.5;   % [ns] 安定判定のΔ閾値
    drift_interval         = 5;     % [s] ドリフトチェック周期
    pulse_amplitude        = 0.01;  % [V] パルス振幅（ao1のみ）
    pulse_duration         = 1;     % [s] パルス時間

    % 状態
    prev_frfr         = NaN;  % 直前の“生”FRFR（ns）
    frfr_offset       = 0;    % 累積補正（…,-400,-200,0,+200,+400,…）
    last_stable_time  = NaN;
    last_drift_time   = NaN;

    %% --- ログ用 ---------------------------------------------------------
    time_log = []; 
    ao1_log  = []; 
    frfr_log = [];  % 修正後FRFR（= raw + offset）を保存

    %% --- 図（上下2段：上=修正FRFR，下=ao1電圧）-----------------------
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

    %% --- 出力初期化 -----------------------------------------------------
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("開始: ao0=%.3f V(固定), ao1=%.3f V(初期)\n", ao0_const, v_ao1);

    %% --- 実時間計測開始 -------------------------------------------------
    t_start = datetime('now');
    stable_buffer = [];  % Δrawの絶対値を入れるバッファ（安定判定用）

    %% --- メインループ ---------------------------------------------------
    while true
        t = seconds(datetime('now') - t_start);  % 実行開始からの経過秒
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            %% 測定（raw FRFRを秒→nsに変換）
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            raw_frfr = frfr_sec * 1e9;  % [ns]

            %% --- ラップ検出 & 補正累積（±200ずつ） -------------------
            if isnan(prev_frfr)
                delta_raw = NaN;
            else
                delta_raw = raw_frfr - prev_frfr;

                % 下方向（≤ -100ns）にラップダウン → +200累積
                if delta_raw <= -JUMP_DETECT_NS
                    frfr_offset = frfr_offset + OFFSET_STEP_NS;
                    fprintf("ラップダウン検出: Δ=%.1f ns → offset += +%d → 合計 %.1f ns\n", ...
                            delta_raw, OFFSET_STEP_NS, frfr_offset);

                % 上方向（≥ +100ns）にラップアップ → -200累積
                elseif delta_raw >= +JUMP_DETECT_NS
                    frfr_offset = frfr_offset - OFFSET_STEP_NS;
                    fprintf("ラップアップ検出: Δ=%.1f ns → offset += -%d → 合計 %.1f ns\n", ...
                            delta_raw, OFFSET_STEP_NS, frfr_offset);
                end
            end

            % 修正後FRFR（これを以降のFB・描画で使用）
            frfr_corrected = raw_frfr + frfr_offset;
            prev_frfr = raw_frfr;  % 次回差分計算用に“生”FRFRを保持

            %% --- 安定判定（従来どおり raw のΔで判定） -----------------
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

            %% --- パルス（ao1のみ） --------------------------------------
            pulse_active = false;
            if is_stable && (isnan(last_drift_time) || t - last_drift_time > drift_interval)
                fprintf("パルス挿入: t=%.1f s\n", t);
                v_ao1 = min(max(v_ao1 + pulse_amplitude, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                pause(pulse_duration);
                v_ao1 = min(max(v_ao1 - pulse_amplitude, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                last_drift_time = t;
                pulse_active = true;
            end

            %% --- FB制御：修正FRFRを用いる --------------------------------
            if pulse_active || isnan(delta_raw) || abs(delta_raw) < frfr_threshold
                fprintf("t=%.1f s | Δraw=%.2f ns < %.1f → ao1=%.4f V維持\n", ...
                        t, delta_raw, frfr_threshold, v_ao1);
            else
                error_ns = frfr_corrected - target;      % 修正FRFRで偏差を評価
                dv = Kp * error_ns; 
                dv = round(dv, 4);
                if abs(dv) < min_step
                    dv = sign(dv) * min_step;
                end
                v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                fprintf("t=%.1f s | FRFRcorr=%.2f ns | error=%.2f | ΔV=%.4f | ao1=%.4f V\n", ...
                        t, frfr_corrected, error_ns, dv, v_ao1);
            end

            %% --- ログ & 描画（修正FRFRを表示） --------------------------
            time_log(end+1) = t;                 %#ok<AGROW>
            ao1_log(end+1)  = v_ao1;             %#ok<AGROW>
            frfr_log(end+1) = frfr_corrected;    %#ok<AGROW>

            set(h_frfr, 'XData', time_log, 'YData', frfr_log);
            set(h_ao1,  'XData', time_log, 'YData', ao1_log);

            % 常に最新30秒を表示（0〜30sは広めに確保）
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

    %% --- 終了処理 -------------------------------------------------------
    % 安全部停止（必要なら ao0 を保持したい場合は [ao0_const, 0] に変更）
    outputSingleScan(s, [0, 0]);
end


function cleanupDAQ(s, dev)
    try, stop(s);    end
    try, release(s); end
    try, clear dev;  end
end


