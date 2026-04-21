function frfr_fb_1010_v6()
    %% --- 初期設定 ---
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定 1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB可変

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev));

    %% --- パラメータ ---
    fb_interval = 0.3; total_time = 180;
    target = 50; Kp = 0.0001;
    frfr_threshold = 0.5; jump_threshold = 50.0;

    ao0_const = 1.54; v_ao1 = 1.54;
    min_voltage = 0.0; max_voltage = 5.0; min_step = 0.001;

    stable_duration = 10; stable_delta_threshold = 0.5;
    drift_interval = 5; pulse_amplitude = 0.01; pulse_duration = 1;

    prev_frfr = NaN;
    last_stable_time = NaN; last_drift_time = NaN;

    %% --- ログ ---
    time_log = []; ao1_log = []; frfr_log = [];

    %% --- 図（上下2段構成）---
    figure('Name','FRFR Feedback Monitor','NumberTitle','off');
    tl = tiledlayout(2,1,'TileSpacing','compact');

    ax1 = nexttile(1);
    h_frfr = plot(ax1, NaN, NaN, 'r-'); grid on;
    ylabel(ax1,'FRFR [ns]');
    title(ax1,'FRFR Over Time');

    ax2 = nexttile(2);
    h_ao1 = plot(ax2, NaN, NaN, 'b-'); grid on;
    ylabel(ax2,'Voltage on ao1 [V]');
    xlabel(ax2,'Time [s]');
    title(ax2,'ao1 Voltage (FB Channel) Over Time');

    linkaxes([ax1, ax2], 'x');

    %% --- 出力初期化 ---
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("開始: ao0=%.3fV固定, ao1=%.3fV初期\n", ao0_const, v_ao1);

    %% --- 実時間計測 ---
    t_start = datetime('now');
    stable_buffer = [];

    %% --- FRFR補正オフセット初期化 ---
    frfr_offset = 0;

    %% --- メインループ ---
    while true
        t = seconds(datetime('now') - t_start); % 実行開始からの経過秒
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            % --- 測定 ---
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr = frfr_sec * 1e9; % ns

            %% --- FRFR補正ロジック（±100ns補正）---
            if isnan(prev_frfr)
                delta = NaN;
            else
                delta = frfr - prev_frfr;

                % 100ns以上下がった → +100補正
                if delta < -100
                    frfr_offset = frfr_offset + 100;
                    fprintf("FRFR急低下検出: Δ=%.1f → +100補正 (合計%.1f)\n", delta, frfr_offset);

                % 100ns以上上がった → -100補正
                elseif delta > 100
                    frfr_offset = frfr_offset - 100;
                    fprintf("FRFR急上昇検出: Δ=%.1f → -100補正 (合計%.1f)\n", delta, frfr_offset);
                end
            end

            % 補正後FRFR
            frfr_corrected = frfr + frfr_offset;
            prev_frfr = frfr;

            %% --- 安定判定 ---
            if ~isnan(delta)
                stable_buffer = [stable_buffer, abs(delta)];
                if numel(stable_buffer) > round(stable_duration/fb_interval)
                    stable_buffer(1) = [];
                end
            end
            is_stable = (numel(stable_buffer) == round(stable_duration/fb_interval)) ...
                        && (max(stable_buffer) < stable_delta_threshold);
            if is_stable && isnan(last_stable_time)
                last_stable_time = t; fprintf("安定検出: %.1f s\n", t);
            elseif ~is_stable
                last_stable_time = NaN;
            end

            %% --- パルス処理 ---
            pulse_active = false;
            if is_stable && (isnan(last_drift_time) || t - last_drift_time > drift_interval)
                fprintf("パルス: t=%.1f s\n", t);
                v_ao1 = min(max(v_ao1 + pulse_amplitude, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                pause(pulse_duration);
                v_ao1 = min(max(v_ao1 - pulse_amplitude, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                last_drift_time = t;
                pulse_active = true;
            end

            %% --- FB制御 ---
            if pulse_active || isnan(delta) || abs(delta) < frfr_threshold
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < %.1f → ao1=%.4f V維持\n", ...
                        t, delta, frfr_threshold, v_ao1);
            else
                error_val = frfr_corrected - target;
                dv = Kp * error_val; dv = round(dv,4);
                if abs(dv) < min_step, dv = sign(dv)*min_step; end
                v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                fprintf("t=%.1f s | frfr_corr=%.2f ns | error=%.2f | ΔV=%.4f | ao1=%.4f V\n", ...
                        t, frfr_corrected, error_val, dv, v_ao1);
            end

            %% --- ログ更新 ---
            time_log(end+1) = t;
            ao1_log(end+1)  = v_ao1;
            frfr_log(end+1) = frfr_corrected;

            %% --- グラフ更新（リアルタイム）---
            set(h_frfr, 'XData', time_log, 'YData', frfr_log);
            set(h_ao1,  'XData', time_log, 'YData', ao1_log);

            % ★ 最新30秒分を常に表示
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

    %% --- 終了処理 ---
    outputSingleScan(s, [0, 0]);
end


function cleanupDAQ(s, dev)
    try, stop(s); end
    try, release(s); end
    try, clear dev; end
end
