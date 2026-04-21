function result = frfr_pulse_after_fb_single_run(delta_v, T_pulse)
%==========================================================================
% FRFR フィードバックで周波数を安定させた後、
% 単発の電圧パルス (Δv, T_pulse) を ao1 に印加する 1 回分実験。
%
% 戻り値 result は構造体：
%   result.delta_v
%   result.T_pulse
%   result.FRFR_before_mean
%   result.FRFR_after_mean
%   result.delta_FRFR_ns
%   result.K_ns_per_Vs   = delta_FRFR / (delta_v * T_pulse)
%   result.csv_name      = ログCSVファイル名
%==========================================================================

    %% -------- パラメータ設定（固定値） --------------------------------
    fb_interval        = 0.3;      % [s] 制御・測定周期 Δt
    Kp                 = 0.0001;   % 周波数誤差に対する P ゲイン
    freq_err_threshold = 0.3;      % [ns/s] これ以下なら FB しない

    JUMP_DETECT_NS     = 50;       % [ns] ラップ検出閾値
    OFFSET_STEP_NS     = 100;      % [ns] オフセット step

    ao0_const          = 1.54;     % [V] 基準 OCXO 側
    v_ao1_init         = 1.54;     % [V] FB の初期待機電圧
    min_voltage        = 0.0;      % [V]
    max_voltage        = 5.0;      % [V]
    min_step           = 0.001;    % [V] 最小ステップ

    % ---- フェーズ時間 --------------------------------------------------
    t_stable      = 60;                % [s] FB で安定させる時間
    t_after       = 60;                % [s] パルス後の観測時間
    t_pulse_start = t_stable;          % パルス開始時刻
    t_pulse_end   = t_stable + T_pulse;% パルス終了時刻
    total_time    = t_stable + T_pulse + t_after;

    % ---- FRFR 前後評価用ウィンドウ ------------------------------------
    pre_window_s   = 20;               % [s] パルス前平均
    % パルス直後 5〜25 秒を after 窓にする（FB の戻しを減らす）
    post_offset_s  = 5;                % [s] パルス終了からのオフセット
    post_window_s  = 20;               % [s] パルス後平均

    % ---- オシロ VISA 情報 ---------------------------------------------
    ip_addr = "192.168.1.61";

    %% -------- DAQ / VISA 初期化 ---------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    dev = visadev("TCPIP0::" + ip_addr + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@()cleanupDAQ(s, dev)); %#ok<NASGU>

    % 初期出力
    v_ao1 = v_ao1_init;
    outputSingleScan(s, [ao0_const, v_ao1]);
    fprintf("\n==== 新しい Run 開始: Δv=%.4f V, T_pulse=%.3f s ====\n", delta_v, T_pulse);
    fprintf("初期状態: ao0=%.3f V, ao1=%.3f V\n", ao0_const, v_ao1);

    %% -------- 状態変数 ------------------------------------------------
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_corrected = NaN;

    pulse_started = false;
    pulse_ended   = false;
    base_v_before_pulse = NaN;

    %% -------- ログ配列 ------------------------------------------------
    time_log      = [];
    frfr_log      = [];
    ao1_log       = [];
    freq_err_log  = [];
    drift_log     = [];
    dv_log        = [];
    phase_log     = [];  % 0: 安定化, 1: パルス, 2: パルス後

    %% -------- メインループ --------------------------------------------
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > total_time
            fprintf("Run 終了 (t=%.2f s)\n", t);
            break;
        end

        % ---- FRFR 計測 ----
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
            raw_frfr = frfr_sec * 1e9;  % [ns]
        catch ME
            warning("オシロ読み出しエラー: %s", ME.message);
            raw_frfr = NaN;
        end

        % ---- アンラップ ----
        if isnan(prev_raw_frfr)
            delta_raw = NaN;
        else
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
            end
        end
        frfr_corrected = raw_frfr + frfr_offset;
        prev_raw_frfr  = raw_frfr;

        % ---- ドリフト・freq_err ----
        if isnan(prev_frfr_corrected)
            drift_ns = NaN;
            freq_err = NaN;
        else
            drift_ns = frfr_corrected - prev_frfr_corrected;
            freq_err = drift_ns / fb_interval;
        end
        prev_frfr_corrected = frfr_corrected;

        % ---- フェーズ判定 ----
        if t < t_pulse_start
            phase = 0;
        elseif t >= t_pulse_start && t < t_pulse_end
            phase = 1;
        else
            phase = 2;
        end

        % ---- 制御ロジック ---------------------------------------------
        dv   = 0;
        vout = v_ao1;

        switch phase
            case 0  % 安定化フェーズ：通常 FB
                if ~isnan(freq_err) && abs(freq_err) >= freq_err_threshold
                    dv = -Kp * freq_err;
                    dv = round(dv, 4);
                    if abs(dv) < min_step
                        dv = min_step * sign(-freq_err);
                    end
                    v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                end
                vout = v_ao1;

            case 1  % パルスフェーズ：FB 更新を止め，ao1 = base+Δv に固定
                if ~pulse_started
                    pulse_started       = true;
                    base_v_before_pulse = v_ao1;
                    fprintf("パルス開始: t=%.1f s | base ao1=%.4f V\n", ...
                        t, base_v_before_pulse);
                end
                vout = base_v_before_pulse + delta_v;

            case 2  % パルス後フェーズ：ao1 を base に戻して FB 再開
                if pulse_started && ~pulse_ended
                    pulse_ended = true;
                    v_ao1 = base_v_before_pulse;
                    fprintf("パルス終了: t=%.1f s | ao1 を base %.4f V に戻して FB 再開\n", ...
                        t, base_v_before_pulse);
                end
                if ~isnan(freq_err) && abs(freq_err) >= freq_err_threshold
                    dv = -Kp * freq_err;
                    dv = round(dv, 4);
                    if abs(dv) < min_step
                        dv = min_step * sign(-freq_err);
                    end
                    v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                end
                vout = v_ao1;
        end

        % ---- 出力 & ログ ----
        try
            outputSingleScan(s, [ao0_const, vout]);
        catch ME
            warning("DAQ 出力エラー: %s", ME.message);
        end

        fprintf("t=%.1f s | phase=%d | FRFR=%.2f ns | freq_err=%.3f ns/s | ao1=%.4f V | dv=%.4f V\n", ...
            t, phase, frfr_corrected, freq_err, vout, dv);

        time_log(end+1)     = t;
        frfr_log(end+1)     = frfr_corrected;
        ao1_log(end+1)      = vout;
        freq_err_log(end+1) = freq_err;
        drift_log(end+1)    = drift_ns;
        dv_log(end+1)       = dv;
        phase_log(end+1)    = phase;

        pause(fb_interval);
    end

    %% -------- CSV 保存 -----------------------------------------------
    time_vec  = time_log(:);
    frfr_vec  = frfr_log(:);
    ao1_vec   = ao1_log(:);
    freq_vec  = freq_err_log(:);
    drift_vec = drift_log(:);
    dv_vec    = dv_log(:);
    phase_vec = phase_log(:);

    log_tbl = table( ...
        time_vec, frfr_vec, ao1_vec, freq_vec, drift_vec, dv_vec, phase_vec, ...
        'VariableNames', ...
        {'time_s','frfr_ns','ao1_V','freq_err_ns_per_s', ...
         'drift_ns','dv_V','phase'} ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    csv_name  = sprintf('frfr_fb_pulse_%.4fV_%s.csv', delta_v, timestamp);
    writetable(log_tbl, csv_name);
    fprintf("CSVログを保存しました: %s\n", csv_name);

    %% -------- パルス前後 FRFR の評価 ----------------------------------
    t_before_start = max(0, t_pulse_start - pre_window_s);
    t_before_end   = t_pulse_start;

    t_after_start  = t_pulse_end + post_offset_s;       % 例: 66 s
    t_after_end    = t_after_start + post_window_s;     % 例: 86 s

    mask_before = (time_vec >= t_before_start) & (time_vec < t_before_end);
    mask_after  = (time_vec >= t_after_start)  & (time_vec < t_after_end);

    frfr_before = frfr_vec(mask_before);
    frfr_after  = frfr_vec(mask_after);

    if isempty(frfr_before) || isempty(frfr_after)
        warning("前後ウィンドウにサンプルが不足");
        FRFR_before_mean = NaN;
        FRFR_after_mean  = NaN;
        delta_FRFR_ns    = NaN;
        K_ns_per_Vs      = NaN;
    else
        FRFR_before_mean = mean(frfr_before, 'omitnan');
        FRFR_after_mean  = mean(frfr_after,  'omitnan');
        delta_FRFR_ns    = FRFR_after_mean - FRFR_before_mean;
        if delta_v ~= 0 && T_pulse > 0
            K_ns_per_Vs = delta_FRFR_ns / (delta_v * T_pulse);
        else
            K_ns_per_Vs = NaN;
        end

        fprintf("\n=== パルス前後 FRFR 概要 ===\n");
        fprintf("  Δv = %.4f V, T_pulse = %.3f s\n", delta_v, T_pulse);
        fprintf("  FRFR_before_mean = %.3f ns (%.1f–%.1f s)\n", ...
            FRFR_before_mean, t_before_start, t_before_end);
        fprintf("  FRFR_after_mean  = %.3f ns (%.1f–%.1f s)\n", ...
            FRFR_after_mean, t_after_start, t_after_end);
        fprintf("  ΔFRFR = %.3f ns\n", delta_FRFR_ns);
        fprintf("  K ≈ %.3f [ns/(V·s)]\n\n", K_ns_per_Vs);
    end

    % 結果構造体
    result = struct();
    result.delta_v           = delta_v;
    result.T_pulse           = T_pulse;
    result.FRFR_before_mean  = FRFR_before_mean;
    result.FRFR_after_mean   = FRFR_after_mean;
    result.delta_FRFR_ns     = delta_FRFR_ns;
    result.K_ns_per_Vs       = K_ns_per_Vs;
    result.csv_name          = csv_name;

    %% -------- 終了時 0V に戻す ---------------------------------------
    try
        outputSingleScan(s, [0, 0]);
        fprintf("終了時: ao0/ao1 を 0 V に戻しました。\n");
    catch
    end
end
