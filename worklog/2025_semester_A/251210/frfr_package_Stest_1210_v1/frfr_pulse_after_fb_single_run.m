function result = frfr_pulse_after_fb_single_run(delta_v, T_pulse, t_stable)
%====================================================================
% FRFR フィードバックで安定化 → 単発パルスを印加 → 前後の FRFR を測り
% ΔFRFR を返す単発実験関数
%
% 入力:
%   delta_v  : パルス振幅 [V]  (ao1 に加える)
%   T_pulse  : パルス幅 [s]
%   t_stable : パルス印加前に FB で安定化しておく時間 [s]
%
% 出力:
%   result.delta_frfr  : パルス前後10秒平均の差分 [ns]
%   result.log_csv     : 保存したログCSVファイル名
%   result.delta_v_V   : パルス振幅 [V]
%   result.T_pulse_s   : パルス幅 [s]
%
% ※ この関数の終了時に ao0/ao1 は [0,0] に戻される
%====================================================================

    %% --- DAQ / オシロ初期化 ---------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % オフセット用
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB/パルス用

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 終了時に必ず 0V + close する
    c = onCleanup(@()cleanupDAQ(s, dev));

    %% --- パラメータ ----------------------------------------------
    fb_interval   = 0.3;        % [s] FB 更新周期
    post_time     = 10;         % [s] パルス後の観測時間
    total_time    = t_stable + T_pulse + post_time;

    ao0_const     = 1.54;       % [V] ao0 固定バイアス
    v_fb          = 1.54;       % [V] ao1 の FB 基準値
    v_min         = 0.0;
    v_max         = 5.0;

    % 周波数誤差に対する P 制御ゲイン
    Kp_freq       = 0.001;      % [V / (ns/s)]
    freq_threshold = 0.30;      % [ns/s] 小さい誤差は無視
    min_step      = 0.001;      % [V] 最小ステップ

    % FRFR アンラップ用
    JUMP_DETECT_NS = 50;        % [ns]
    OFFSET_STEP_NS = 100;       % [ns]

    % パルス時刻
    t_pulse_start = t_stable;
    t_pulse_end   = t_pulse_start + T_pulse;

    % ΔFRFR 計算用窓
    pre_margin   = 3;   % [s]
    post_margin  = 3;   % [s]
    pre_window   = 10;  % [s]
    post_window  = 10;  % [s]

    %% --- 状態変数 ------------------------------------------------
    prev_raw_frfr       = NaN;
    frfr_offset         = 0;
    prev_frfr_corrected = NaN;

    %% --- ログ用配列 ----------------------------------------------
    time_log      = [];
    frfr_log      = [];
    freq_err_log  = [];
    ao1_log       = [];
    drift_log     = [];
    dv_log        = [];
    phase_log     = [];   % 0:FB安定化, 1:パルス, 2:パルス後

    %% --- 初期出力 -----------------------------------------------
    outputSingleScan(s, [ao0_const, v_fb]);
    fprintf("single_run: start | ΔV=%.3f V, T_pulse=%.3f s, t_stable=%.1f s\n", ...
            delta_v, T_pulse, t_stable);

    %% --- メインループ -------------------------------------------
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > total_time
            fprintf("single_run: total_time reached (%.1f s)\n", t);
            break;
        end

        % フェーズ判定
        if t < t_pulse_start
            phase = 0;   % 安定化
        elseif t < t_pulse_end
            phase = 1;   % パルス中
        else
            phase = 2;   % パルス後
        end

        % ---- FRFR 計測 ------------------------------------------
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        raw_frfr = frfr_sec * 1e9;   % [ns]

        % ---- アンラップ -----------------------------------------
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
        frfr_corr     = raw_frfr + frfr_offset;
        prev_raw_frfr = raw_frfr;

        % ---- freq_err 計算 --------------------------------------
        if isnan(prev_frfr_corrected)
            drift_ns = NaN;
            freq_err = NaN;
        else
            drift_ns = frfr_corr - prev_frfr_corrected;
            freq_err = drift_ns / fb_interval;  % [ns/s]
        end
        prev_frfr_corrected = frfr_corr;

        % ---- FB 制御（パルス中は FB 更新しない） ----------------
        dv_fb = 0;
        if phase ~= 1      % パルス中以外のみ FB
            if ~isnan(freq_err) && abs(freq_err) >= freq_threshold
                dv_fb = -Kp_freq * freq_err;
                dv_fb = round(dv_fb, 4);

                if abs(dv_fb) < min_step
                    dv_fb = min_step * sign(-freq_err);
                end

                v_fb = v_fb + dv_fb;
                v_fb = min(max(v_fb, v_min), v_max);
            end
        end

        % ---- 実際に出す電圧（パルス中は delta_v を足す） -------
        if phase == 1
            v_out = v_fb + delta_v;
        else
            v_out = v_fb;
        end
        v_out = min(max(v_out, v_min), v_max);

        try
            outputSingleScan(s, [ao0_const, v_out]);
        catch ME
            warning("DAQ output error: %s", ME.message);
            break;
        end

        % ---- ログ ------------------------------------------------
        time_log(end+1)     = t;          %#ok<AGROW>
        frfr_log(end+1)     = frfr_corr;  %#ok<AGROW>
        freq_err_log(end+1) = freq_err;   %#ok<AGROW>
        ao1_log(end+1)      = v_out;      %#ok<AGROW>
        drift_log(end+1)    = drift_ns;   %#ok<AGROW>
        dv_log(end+1)       = dv_fb;      %#ok<AGROW>
        phase_log(end+1)    = phase;      %#ok<AGROW>

        fprintf("t=%.1f s | phase=%d | FRFR=%.2f ns | freq_err=%.3f ns/s | ao1=%.4f V | dv_fb=%.4f V\n", ...
                t, phase, frfr_corr, freq_err, v_out, dv_fb);

        pause(fb_interval);
    end

    %% --- CSV ログ保存 -------------------------------------------
    time_vec     = time_log(:);
    frfr_vec     = frfr_log(:);
    freq_err_vec = freq_err_log(:);
    ao1_vec      = ao1_log(:);
    drift_vec    = drift_log(:);
    dv_vec       = dv_log(:);
    phase_vec    = phase_log(:);

    log_tbl = table( ...
        time_vec, frfr_vec, freq_err_vec, ao1_vec, ...
        drift_vec, dv_vec, phase_vec, ...
        'VariableNames', ...
        {'time_s','frfr_ns','freq_err_ns_per_s', ...
         'ao1_V','drift_ns','dv_fb_V','phase'} );

    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_fb_pulse_%.2fV_%.2fs_%s.csv', ...
                        delta_v, T_pulse, timestamp);
    writetable(log_tbl, log_name);
    fprintf("single_run: log saved: %s\n", log_name);

    %% --- パルス前後の ΔFRFR を計算 -------------------------------
    % ここでは、t_pulse_start, t_pulse_end, pre/post window を使う
    t = time_vec;
    fr = frfr_vec;

    t_pre_start  = t_pulse_start - pre_margin - pre_window;
    t_pre_end    = t_pulse_start - pre_margin;
    t_post_start = t_pulse_end   + post_margin;
    t_post_end   = t_pulse_end   + post_window + post_margin;

    mask_pre  = (t >= t_pre_start)  & (t <  t_pre_end);
    mask_post = (t >= t_post_start) & (t <= t_post_end);

    fr_pre  = fr(mask_pre);
    fr_post = fr(mask_post);

    if numel(fr_pre) < 3 || numel(fr_post) < 3
        warning("ΔFRFR: 前後窓のデータが不足しています。delta_frfr を NaN にします。");
        delta_frfr = NaN;
    else
        m_pre  = mean(fr_pre,  'omitnan');
        m_post = mean(fr_post, 'omitnan');
        delta_frfr = m_post - m_pre;

        fprintf("=== パルス前後の FRFR 概要 ===\n");
        fprintf("  FRFR_before_mean = %.3f ns\n", m_pre);
        fprintf("  FRFR_after_mean  = %.3f ns\n", m_post);
        fprintf("  ΔFRFR = %.3f ns\n", delta_frfr);
    end

    %% --- 結果構造体 ---------------------------------------------
    result = struct();
    result.delta_frfr  = delta_frfr;
    result.log_csv     = log_name;
    result.delta_v_V   = delta_v;
    result.T_pulse_s   = T_pulse;

    % onCleanup によりここで ao0/ao1=[0,0] になり、DAQ/オシロが解放される
end
