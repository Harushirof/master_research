function frfr_fb_v5_0710()
    % ——— 初期設定 ———
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 制御パラメータ
    fb_interval = 0.3;         % フィードバック周期 [s]
    total_time = 180;           % 実行時間 [s]
    target = 50;               % 目標FRFR [ns]
    Kp = 0.0001;               % 比例ゲイン（固定）
    frfr_threshold = 0.5;      % ΔFRFR無視閾値 [ns]
    jump_threshold = 50.0;     % unwrapジャンプ検出閾値 [ns]
    voltage = 0.01;            % 初期電圧 [V]
    min_voltage = 0.0;
    max_voltage = 5.0;
    min_step = 0.001;          % 電圧最小ステップ [V]

    % unwrap用変数
    prev_frfr = NaN;
    jump_index = 0;

    % 出力初期化
    outputSingleScan(s, voltage);
    fprintf("ジャンプ積算 unwrap + index 表示付き 制御開始\n");

    % 時間計測開始
    t_start = tic;

    while true
        t = toc(t_start);
        if t > total_time
            fprintf("制御終了\n");
            break;
        end

        try
            % オシロからFRFR取得
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            frfr = frfr_sec * 1e9;  % [s] → [ns]

            % unwrap処理
            if isnan(prev_frfr)
                unwrap_frfr = frfr;
                delta = NaN;
            else
                delta = frfr - prev_frfr;

                % ジャンプ検出とindex更新
                if delta > jump_threshold
                    jump_index = jump_index + 1;
                elseif delta < -jump_threshold
                    jump_index = jump_index - 1;
                end

                unwrap_frfr = frfr + jump_index * 100;
            end
            prev_frfr = frfr;

            % ΔFRFRが小さい場合はスキップ
            if isnan(delta) || abs(delta) < frfr_threshold
                fprintf("t=%.1f s | ΔFRFR=%.2f ns < %.1fns → 電圧維持 (%.3f V)\n", ...
                    t, delta, frfr_threshold, voltage);
                pause(fb_interval);
                continue;
            end

            % 誤差計算・電圧調整
            error = unwrap_frfr - target;
            delta_v = Kp * error;
            delta_v = round(delta_v, 4);  % 微小値制限
            if abs(delta_v) < min_step
                delta_v = sign(delta_v) * min_step;
            end

            voltage = voltage + delta_v;
            voltage = max(min_voltage, min(max_voltage, voltage));
            outputSingleScan(s, voltage);

            % 表示
            fprintf("t=%.1f s | FRFR=%.2f ns | Jump=%d | unwrap=%.2f ns | 誤差=%.2f ns | ΔV=%.4f | V=%.3f\n", ...
                t, frfr, jump_index, unwrap_frfr, error, delta_v, voltage);

            pause(fb_interval);

        catch ME
            warning("エラー発生: %s", ME.message);
            break;
        end
    end

    % 終了処理
    outputSingleScan(s, 0);
    release(s);
    clear dev;
end