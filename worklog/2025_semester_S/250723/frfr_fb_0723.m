function frfr_fb_with_pulse_and_plot_v1()
    % --- 初期設定 ---
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 制御パラメータ
    fb_interval = 0.3;
    total_time = 180;
    target = 50;
    Kp = 0.0001;
    frfr_threshold = 0.5;
    jump_threshold = 50.0;
    voltage = 0.01;
    min_voltage = 0.0;
    max_voltage = 5.0;
    min_step = 0.001;

    % 安定判定・パルス制御用
    stable_duration = 10;
    stable_delta_threshold = 0.5 %安定判定用ΔFRFR閾値
    drift_interval = 5; %ドリフトチェックの周期
    drift_threshold = 2.0; %ドリフト判定用の閾値
    pulse_amplitude = 0.01; %パルス電圧
    pulse_duration = 1;

    % unwrapと履歴記録
    prev_frfr = NaN;
    jump_index = 0;
    prev_volt = voltage;
    last_stable_time = NaN;
    last_drift_time = NaN;

    time_log = [];
    volt_log = [];

    % グラフ初期化
    figure;
    h_plot = plot(NaN, NaN, 'b-');
    xlabel('Time [s]');
    ylabel('Voltage [V]');
    title('Voltage Output Over Time');
    grid on;
    hold on;

    outputSingleScan(s, voltage);
    fprintf("制御開始\n");

    t_start = tic;
    stable_buffer = [];

    while true
        t = toc(t_start);
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            % 測定
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr = frfr_sec * 1e9;

            % unwrap
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
                unwrap_frfr = frfr + jump_index * 100;
            end
            prev_frfr = frfr;

            % 安定性バッファ更新
            if ~isnan(delta)
                stable_buffer = [stable_buffer, abs(delta)];
                if numel(stable_buffer) > round(stable_duration / fb_interval)
                    stable_buffer(1) = [];  % 古い値を削除
                end
            end

            % 安定状態判定
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

            % パルス挿入
            pulse_active = false;
            if is_stable && (isnan(last_drift_time) || t - last_drift_time > drift_interval)
                fprintf("パルス挿入: t=%.1f s\n", t);
                voltage = voltage + pulse_amplitude;
                voltage = min(max(voltage, min_voltage), max_voltage);
                outputSingleScan(s, voltage);
                pause(pulse_duration);
                voltage = voltage - pulse_amplitude;
                voltage = min(max(voltage, min_voltage), max_voltage);
                outputSingleScan(s, voltage);
                last_drift_time = t;
                pulse_active = true;
            end

            % ΔFRFRが小さい or パルス中はスキップ
            if pulse_active || isnan(delta) || abs(delta) < frfr_threshold
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < %.1fns → 電圧維持 (%.3f V)\n", ...
                    t, delta, frfr_threshold, voltage);
                time_log(end+1) = t;
                volt_log(end+1) = voltage;
                set(h_plot, 'XData', time_log, 'YData', volt_log);
                drawnow limitrate;
                pause(fb_interval);
                continue;
            end

            % FB制御（P制御）
            error = unwrap_frfr - target;
            delta_v = Kp * error;
            delta_v = round(delta_v, 4);
            if abs(delta_v) < min_step
                delta_v = sign(delta_v) * min_step;
            end
            voltage = voltage + delta_v;
            voltage = min(max(voltage, min_voltage), max_voltage);
            outputSingleScan(s, voltage);

            fprintf("t=%.1f s | unwrap=%.2f ns | error=%.2f ns | ΔV=%.4f | V=%.3f\n", ...
                t, unwrap_frfr, error, delta_v, voltage);

            % ログ・プロット更新
            time_log(end+1) = t;
            volt_log(end+1) = voltage;
            set(h_plot, 'XData', time_log, 'YData', volt_log);
            drawnow limitrate;

            pause(fb_interval);

        catch ME
            warning("エラー発生: %s", ME.message);
            break;
        end
    end

    outputSingleScan(s, 0);
    release(s);
    clear dev;
end
