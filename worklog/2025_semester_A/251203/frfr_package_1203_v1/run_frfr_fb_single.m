function run_log = run_frfr_fb_single(s, dev, params, run_idx)
% 1回分の FRFR FB を実行し、ログ構造体を返す関数
% （リアルタイムプロットは省略し、ログ＋コンソール出力中心）

    fb_interval        = params.fb_interval;
    total_time         = params.total_time;
    Kp                 = params.Kp;
    freq_err_threshold = params.freq_err_threshold;

    JUMP_DETECT_NS     = params.JUMP_DETECT_NS;
    OFFSET_STEP_NS     = params.OFFSET_STEP_NS;

    ao0_const          = params.ao0_const;
    v_ao1              = params.ao1_init;
    min_voltage        = params.min_voltage;
    max_voltage        = params.max_voltage;
    min_step           = params.min_step;

    % --- 状態変数 ---
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_corrected = NaN;

    % --- ログ用配列 ---
    time_log      = [];
    frfr_log      = [];
    ao1_log       = [];
    drift_log     = [];  % ΔFRFR per step [ns]
    freq_err_log  = [];  % ΔFRFR/Δt [ns/s]
    delta_raw_log = [];
    dv_log        = [];

    % --- 初期出力 ---
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("Run %d: ao0=%.3f V (固定), ao1=%.3f V (初期)\n", ...
        run_idx, ao0_const, v_ao1);

    % --- 計測開始 ---
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > total_time
            fprintf("Run %d: 制御終了\n", run_idx);
            break;
        end

        try
            %% --- 測定 ---
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            raw_frfr = frfr_sec * 1e9; % [ns]

            %% --- FRFR補正（アンラップ） ---
            if isnan(prev_raw_frfr)
                delta_raw = NaN;
            else
                delta_raw = raw_frfr - prev_raw_frfr;

                if delta_raw <= -JUMP_DETECT_NS
                    frfr_offset = frfr_offset + OFFSET_STEP_NS;
                    fprintf("Run %d: ラップダウン: Δ=%.1f → offset=%.1f\n", ...
                        run_idx, delta_raw, frfr_offset);

                elseif delta_raw >= +JUMP_DETECT_NS
                    frfr_offset = frfr_offset - OFFSET_STEP_NS;
                    fprintf("Run %d: ラップアップ:  Δ=%.1f → offset=%.1f\n", ...
                        run_idx, delta_raw, frfr_offset);
                end
            end

            frfr_corrected = raw_frfr + frfr_offset;
            prev_raw_frfr  = raw_frfr;

            %% --- ドリフトと周波数誤差計算 ---
            if isnan(prev_frfr_corrected)
                drift_ns = NaN;   % [ns/step]
                freq_err = NaN;   % [ns/s]
            else
                drift_ns = frfr_corrected - prev_frfr_corrected;  % ΔFRFR per step [ns]
                freq_err = drift_ns / fb_interval;                % ΔFRFR/Δt [ns/s] ≒ 周波数誤差
            end
            prev_frfr_corrected = frfr_corrected;

            %% --- FB制御（FRFRの傾き＝周波数誤差に対するP制御） ---
            dv = 0;  % [V] ログ用

            if isnan(freq_err) || abs(freq_err) < freq_err_threshold
                % 周波数誤差が十分小さいので制御しない
                fprintf("Run %d | t=%.1f s | FRFR=%.2f ns | freq_err=%.3f ns/s < %.2f → ao1維持\n", ...
                    run_idx, t, frfr_corrected, freq_err, freq_err_threshold);

            else
                % 周波数誤差が大きい → P 制御
                dv = -Kp * freq_err;   % 傾きに比例して電圧を変更
                dv = round(dv, 4);

                if abs(dv) < min_step
                    dv = min_step * sign(-freq_err);
                end

                v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                outputSingleScan(s, [ao0_const, v_ao1]);

                fprintf("Run %d | t=%.1f s | FRFR=%.2f ns | drift=%.3f ns | freq_err=%.3f ns/s | ΔV=%.4f | ao1=%.4f V\n", ...
                    run_idx, t, frfr_corrected, drift_ns, freq_err, dv, v_ao1);
            end

            %% --- ログ格納 ---
            time_log(end+1)      = t;
            frfr_log(end+1)      = frfr_corrected;
            ao1_log(end+1)       = v_ao1;
            drift_log(end+1)     = drift_ns;
            freq_err_log(end+1)  = freq_err;
            delta_raw_log(end+1) = delta_raw;
            dv_log(end+1)        = dv;

            pause(fb_interval);

        catch ME
            warning("Run %d: エラー: %s", run_idx, ME.message);
            break;
        end
    end

    %% --- ログ構造体にまとめる ---
    run_log.time_s            = time_log(:);
    run_log.frfr_corrected_ns = frfr_log(:);
    run_log.ao1_V             = ao1_log(:);
    run_log.drift_ns          = drift_log(:);
    run_log.freq_err_ns_per_s = freq_err_log(:);
    run_log.delta_raw_ns      = delta_raw_log(:);
    run_log.dv_V              = dv_log(:);

    %% --- CSV 保存 ---
    log_tbl = table( ...
        run_log.time_s, ...
        run_log.frfr_corrected_ns, ...
        run_log.ao1_V, ...
        run_log.drift_ns, ...
        run_log.freq_err_ns_per_s, ...
        run_log.delta_raw_ns, ...
        run_log.dv_V, ...
        'VariableNames', ...
        { ...
            'time_s', ...
            'frfr_corrected_ns', ...
            'ao1_V', ...
            'drift_ns_per_step', ...
            'freq_err_ns_per_s', ...
            'delta_raw_ns', ...
            'dv_V' ...
        } ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    filename  = sprintf('frfr_log_run%02d_%s.csv', run_idx, timestamp);
    writetable(log_tbl, filename);
    fprintf("Run %d: CSVログを保存しました: %s\n", run_idx, filename);
end
