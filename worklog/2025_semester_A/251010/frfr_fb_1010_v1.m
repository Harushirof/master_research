function frfr_fb_with_pulse_and_plot_v2()
    % --- 初期設定 ---
    s = daq.createSession('ni');
    % ao0(定常1.54V) と ao1(FB可変) を追加
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定: 1.54V
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % 可変: FB用

    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % --- 制御パラメータ ---
    fb_interval = 0.3;         % フィードバック周期[s]
    total_time  = 180;         % 実行時間[s]
    target      = 50;          % 目標(ns)
    Kp          = 0.0001;      % 比例ゲイン
    frfr_threshold  = 0.5;     % |ΔFRFR| がこれ未満なら保持
    jump_threshold  = 50.0;    % unwrap用ジャンプ判定(ns)

    ao0_const = 1.54;          % ★ ao0 は常に 1.54 V
    v_ao1     = 1.54;          % ★ ao1 初期値も 1.54 V（従来の0V→1.54Vへ変更）
    min_voltage = 0.0;         % ao1 下限
    max_voltage = 5.0;         % ao1 上限
    min_step    = 0.001;       % ao1 最小ステップ[V]

    % --- 安定判定・パルス制御 ---
    stable_duration      = 10;     % 安定判定窓[s]
    stable_delta_threshold = 0.5;  % ★ セミコロン漏れ修正
    drift_interval       = 5;      % ドリフトチェック周期[s]
    drift_threshold      = 2.0;    % （未使用だが残置）
    pulse_amplitude      = 0.01;   % パルス電圧[V]
    pulse_duration       = 1;      % パルス時間[s]

    % unwrapと履歴記録
    prev_frfr = NaN;
    jump_index = 0;
    last_stable_time = NaN;
    last_drift_time  = NaN;

    time_log = [];
    ao1_log  = [];

    % --- グラフ初期化（ao1 の推移のみ表示）---
    figure;
    h_plot = plot(NaN, NaN, 'b-');
    xlabel('Time [s]');
    ylabel('Voltage on ao1 [V]');
    title('ao1 Voltage (FB Channel) Over Time');
    grid on; hold on;

    % ★ 初期出力（ao0=1.54V固定, ao1=1.54V初期）
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("制御開始: ao0=%.3f V (固定), ao1=%.3f V (初期)\n", ao0_const, v_ao1);

    t_start = tic;
    stable_buffer = [];

    while true
        t = toc(t_start);
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            % --- 測定 ---
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr = frfr_sec * 1e9;   % ns へ

            % --- unwrap ---
            if isnan(prev_frfr)
                unwrap_frfr = frfr;
                delta = NaN;
            else
                delta = frfr - prev_frfr;
                if delta > jump_threshold
                    jump_index = jump_index + 1;
                elseif delta < -jump_threshold
                    jump_index = jump_index - 1;
                end
                unwrap_frfr = frfr + jump_index * 100; % 100ns刻みで巻き取り
            end
            prev_frfr = frfr;

            % --- 安定性バッファ更新 ---
            if ~isnan(delta)
                stable_buffer = [stable_buffer, abs(delta)];
                if numel(stable_buffer) > round(stable_duration / fb_interval)
                    stable_buffer(1) = [];
                end
            end

            % --- 安定状態判定 ---
            is_stable = false;
            if length(stable_buffer) == round(stable_duration / fb_interval)
                if max(stable_buffer) < stable_delta_threshold
                    is_stable = true;
                    if isnan(last_stable_time)
                        last_stable_time = t;
                        fprintf("安定状態を検出: %.1f s\n", t);
                    end
                else
                    last_stable_time = NaN;
                end
            end

            % --- パルス挿入（ao1 のみに適用）---
            pulse_active = false;
            if is_stable && (isnan(last_drift_time) || t - last_drift_time > drift_interval)
                fprintf("パルス挿入: t=%.1f s (ao1)\n", t);
                v_ao1 = v_ao1 + pulse_amplitude;
                v_ao1 = min(max(v_ao1, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                pause(pulse_duration);
                v_ao1 = v_ao1 - pulse_amplitude;
                v_ao1 = min(max(v_ao1, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);
                last_drift_time = t;
                pulse_active = true;
            end

            % --- |ΔFRFR| が小さい or パルス中は保持（ao1電圧維持）---
            if pulse_active || isnan(delta) || abs(delta) < frfr_threshold
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < %.1f ns → ao1電圧維持 (%.3f V)\n", ...
                        t, delta, frfr_threshold, v_ao1);
                time_log(end+1) = t;
                ao1_log(end+1)  = v_ao1;
                set(h_plot, 'XData', time_log, 'YData', ao1_log);
                drawnow limitrate;
                pause(fb_interval);
                continue;
            end

            % --- FB制御（P制御：ao1のみ更新）---
            error   = unwrap_frfr - target;
            delta_v = Kp * error;
            delta_v = round(delta_v, 4);
            if abs(delta_v) < min_step
                delta_v = sign(delta_v) * min_step;
            end
            v_ao1 = v_ao1 + delta_v;
            v_ao1 = min(max(v_ao1, min_voltage), max_voltage);
            outputSingleScan(s, [ao0_const, v_ao1]);

            fprintf("t=%.1f s | unwrap=%.2f ns | error=%.2f ns | ΔV=%.4f | ao1=%.3f\n", ...
                    t, unwrap_frfr, error, delta_v, v_ao1);

            % --- ログ・描画 ---
            time_log(end+1) = t;
            ao1_log(end+1)  = v_ao1;
            set(h_plot, 'XData', time_log, 'YData', ao1_log);
            drawnow limitrate;

            pause(fb_interval);

        catch ME
            warning("エラー発生: %s", ME.message);
            break;
        end
    end

    % ★ 終了時は両チャネルを 0 V に（必要に応じて ao0 を維持したい場合は [ao0_const, 0] に変更）
    outputSingleScan(s, [0, 0]);
    release(s);
    clear dev;
end
