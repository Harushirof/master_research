function frfr_pulse_after_fb_single()
%==========================================================================
% FRFR フィードバックで周波数を安定させた後、
% 単発の電圧パルスを ao1 に印加し、
% その前後で FRFR がどれだけ変化するかを測る 1 回分の実験。
%
% フェーズ構成：
%   1) 安定化フェーズ: FB ロジックあり（freq_err に対する P 制御）
%   2) パルスフェーズ: FB 更新を一時停止し、ao1 = base_v + Δv に固定
%   3) パルス後フェーズ: ao1 を base_v に戻し、再び FB ロジックを有効化
%
% 出力：
%   - ログ CSV
%   - コンソールに FRFR_before / FRFR_after / ΔFRFR の概算
%==========================================================================

    %% -------- パラメータ設定 ------------------------------------------
    % ---- FB ロジック関連（いま使っているものと整合させてください） ----
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

    % ---- フェーズ時間設定 ---------------------------------------------
    t_stable          = 60;        % [s] FB で安定させる時間
    T_pulse           = 1.0;       % [s] パルス幅
    t_after           = 60;        % [s] パルス後の観測時間
    t_pulse_start     = t_stable;          % パルス開始時刻
    t_pulse_end       = t_stable + T_pulse;% パルス終了時刻
    total_time        = t_stable + T_pulse + t_after;

    % ---- パルス条件 ----------------------------------------------------
    delta_v           = 0.1;     % [V] パルス振幅（例: +5 mV）

    % ---- FRFR 前後評価用ウィンドウ ------------------------------------
    pre_window_s      = 20;        % [s] パルス前平均 (t_pulse_start - pre_window_s ～ start)
    post_window_s     = 20;        % [s] パルス後平均 (total_time - post_window_s ～ total)

    % ---- オシロ VISA 情報 ---------------------------------------------
    ip_addr           = "192.168.1.61";

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
    fprintf("初期状態: ao0=%.3f V, ao1=%.3f V\n", ao0_const, v_ao1);

    %% -------- 状態変数 ------------------------------------------------
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_corrected = NaN;

    % パルス関連
    pulse_started = false;
    pulse_ended   = false;
    base_v_before_pulse = NaN;

    %% -------- ログ ----------------------------------------------------
    time_log      = [];
    frfr_log      = [];
    ao1_log       = [];
    freq_err_log  = [];
    drift_log     = [];
    dv_log        = [];
    phase_log     = [];   % 0: 安定化, 1: パルス中, 2: パルス後

    %% -------- メインループ --------------------------------------------
    fprintf("FB + パルス実験開始 (total_time = %.1f s)\n", total_time);
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > total_time
            fprintf("実験終了 (t=%.2f s)\n", t);
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

        % ---- アンラップ処理 ----
        if isnan(prev_raw_frfr)
            delta_raw = NaN;
        else
            delta_raw = raw_frfr - prev_raw_frfr;

            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
                fprintf("ラップダウン: Δ=%.1f → offset=%.1f\n", ...
                    delta_raw, frfr_offset);
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
                fprintf("ラップアップ:  Δ=%.1f → offset=%.1f\n", ...
                    delta_raw, frfr_offset);
            end
        end
        frfr_corrected = raw_frfr + frfr_offset;
        prev_raw_frfr  = raw_frfr;

        % ---- ドリフト・周波数誤差 ----
        if isnan(prev_frfr_corrected)
            drift_ns = NaN;
            freq_err = NaN;
        else
            drift_ns = frfr_corrected - prev_frfr_corrected;  % [ns/step]
            freq_err = drift_ns / fb_interval;                % [ns/s]
        end
        prev_frfr_corrected = frfr_corrected;

        % ---- フェーズ判定 ----
        if t < t_pulse_start
            phase = 0;   % 安定化フェーズ
        elseif t >= t_pulse_start && t < t_pulse_end
            phase = 1;   % パルスフェーズ
        else
            phase = 2;   % パルス後フェーズ
        end

        % ---- 制御（FB + パルス） -------------------------------------
        dv   = 0;
        vout = v_ao1;  % 出力電圧（ao1）

        switch phase
            case 0  % 安定化: 通常の FB
                if isnan(freq_err) || abs(freq_err) < freq_err_threshold
                    % 何もしない
                else
                    dv = -Kp * freq_err;
                    dv = round(dv, 4);

                    if abs(dv) < min_step
                        dv = min_step * sign(-freq_err);
                    end

                    v_ao1 = min(max(v_ao1 + dv, min_voltage), max_voltage);
                end
                vout = v_ao1;

            case 1  % パルス中: FB 更新は止め、電圧を base_v + Δv に固定
                if ~pulse_started
                    pulse_started       = true;
                    base_v_before_pulse = v_ao1; % 直前の FB 電圧を記録
                    fprintf("パルス開始: t=%.1f s | base ao1 = %.4f V\n", ...
                        t, base_v_before_pulse);
                end
                vout = base_v_before_pulse + delta_v;
                % v_ao1 自体はここでは更新しない（パルス終了後に base から再スタート）

            case 2  % パルス後: ao1 を base_v に戻し、FB 再開
                if pulse_started && ~pulse_ended
                    pulse_ended = true;
                    v_ao1 = base_v_before_pulse;  % ベースに戻してから再スタート
                    fprintf("パルス終了: t=%.1f s | ao1 を base %.4f V に戻して FB 再開\n", ...
                        t, base_v_before_pulse);
                end

                if isnan(freq_err) || abs(freq_err) < freq_err_threshold
                    % 何もしない
                else
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

    %% -------- ログを CSV で保存 --------------------------------------
    time_vec  = time_log(:);
    frfr_vec  = frfr_log(:);
    ao1_vec   = ao1_log(:);
    freq_vec  = freq_err_log(:);
    drift_vec = drift_log(:);
    dv_vec    = dv_log(:);
    phase_vec = phase_log(:);

    log_tbl = table( ...
        time_vec, ...
        frfr_vec, ...
        ao1_vec, ...
        freq_vec, ...
        drift_vec, ...
        dv_vec, ...
        phase_vec, ...
        'VariableNames', ...
        {'time_s','frfr_ns','ao1_V','freq_err_ns_per_s', ...
         'drift_ns','dv_V','phase'} ...
    );

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    csv_name  = sprintf('frfr_fb_pulse_%s.csv', timestamp);
    writetable(log_tbl, csv_name);
    fprintf("CSVログを保存しました: %s\n", csv_name);

    %% -------- パルス前後の FRFR をざっくり評価 -----------------------
    % 前後 20 s (pre_window_s, post_window_s) の平均を比較する
    t_before_start = max(0, t_pulse_start - pre_window_s);
    t_before_end   = t_pulse_start;
    t_after_start  = total_time - post_window_s;
    t_after_end    = total_time;

    mask_before = (time_vec >= t_before_start) & (time_vec < t_before_end);
    mask_after  = (time_vec >= t_after_start)  & (time_vec <= t_after_end);

    frfr_before = frfr_vec(mask_before);
    frfr_after  = frfr_vec(mask_after);

    if isempty(frfr_before) || isempty(frfr_after)
        warning("前後ウィンドウに十分なサンプルが無いため FRFR 差分は計算しません。");
    else
        FRFR_before_mean = mean(frfr_before,'omitnan');
        FRFR_after_mean  = mean(frfr_after,'omitnan');
        delta_FRFR_ns    = FRFR_after_mean - FRFR_before_mean;

        fprintf("\n=== パルス前後の FRFR 概要 ===\n");
        fprintf("  パルス条件: Δv = %.4f V, T_pulse = %.3f s\n", delta_v, T_pulse);
        fprintf("  FRFR_before_mean = %.3f ns (t in [%.1f, %.1f) s)\n", ...
            FRFR_before_mean, t_before_start, t_before_end);
        fprintf("  FRFR_after_mean  = %.3f ns (t in [%.1f, %.1f] s)\n", ...
            FRFR_after_mean, t_after_start, t_after_end);
        fprintf("  ΔFRFR = FRFR_after - FRFR_before = %.3f ns\n", delta_FRFR_ns);
        fprintf("  （この ΔFRFR が「単発パルスでどれだけ位相がずれたか」の１つの目安）\n");
    end

    %% -------- 終了時 0V に戻す ---------------------------------------
    try
        outputSingleScan(s, [0, 0]);
        fprintf("\n終了時: ao0/ao1 を 0 V に戻しました。\n");
    catch
    end
end
