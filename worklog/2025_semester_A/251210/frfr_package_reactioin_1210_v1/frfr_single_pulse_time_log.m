function log_filename = frfr_single_pulse_time_log(DeltaV, Tpulse, baseline_time, post_time)
% 1 回分の FRFR ログ取得
%   Phase 0: baseline_time [s] だけ FB で FRFR を安定化
%   Phase 1: Tpulse [s] だけ ΔV をパルス印加（FB 停止）
%   Phase 2: post_time [s] だけ FRFR を観測
%
% 測定間隔: fb_interval = 0.3 s
%
% 出力:
%   log_filename : 保存した CSV ファイル名
%
% ログ列:
%   time_s, frfr_ns, ao1_V, phase
%   phase: 0=FB安定化, 1=パルス中, 2=パルス後

    %% ---- DAQ 初期化 ---------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');  % 固定オフセット
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');  % FB/パルス用

    ao0_const = 1.54;    % [V] 固定オフセット
    v_fb      = 1.54;    % [V] FB 用電圧（パルスベース）
    v_min     = 0.0;
    v_max     = 5.0;

    outputSingleScan(s, [ao0_const, v_fb]);

    %% ---- オシロ初期化 -------------------------------------------
    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 終了時に必ず 0V + 解放
    c = onCleanup(@() cleanupDAQ(s, dev));

    %% ---- パラメータ ---------------------------------------------
    fb_interval = 0.3;        % [s] 測定周期
    Kp_freq     = 0.001;      % [V / (ns/s)] 周波数誤差に対する P ゲイン
    freq_thresh = 0.30;       % [ns/s] 小さい誤差は無視
    min_step    = 0.001;      % [V] 最小ステップ

    total_time = baseline_time + Tpulse + post_time;

    t_pulse_start = baseline_time;
    t_pulse_end   = baseline_time + Tpulse;

    %% ---- ログ用変数 ---------------------------------------------
    time_log = [];
    frfr_log = [];
    ao1_log  = [];
    phase_log = [];

    prev_frfr = NaN;

    fprintf("single_run: ΔV=%.3f V, Tpulse=%.3f s, baseline=%.1f s, post=%.1f s\n", ...
            DeltaV, Tpulse, baseline_time, post_time);

    t0 = datetime('now');

    %% ---- メインループ -------------------------------------------
    while true
        t = seconds(datetime('now') - t0);
        if t > total_time
            fprintf("single_run: total_time=%.1f s 到達 → 終了\n", t);
            break;
        end

        % phase 判定
        if t < t_pulse_start
            phase = 0;   % FB安定化
        elseif t < t_pulse_end
            phase = 1;   % パルス中
        else
            phase = 2;   % パルス後
        end

        % ---- FRFR 測定 ------------------------------------------
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        frfr_ns = frfr_sec * 1e9;

        % ---- 周波数誤差計算（drift / dt） ----------------------
        if isnan(prev_frfr)
            freq_err = NaN;
        else
            freq_err = (frfr_ns - prev_frfr) / fb_interval;  % [ns/s]
        end
        prev_frfr = frfr_ns;

        % ---- FB 更新（phase 0,2 のときだけ） -------------------
        dv_fb = 0;
        if phase ~= 1
            if ~isnan(freq_err) && abs(freq_err) >= freq_thresh
                dv_fb = -Kp_freq * freq_err;
                dv_fb = round(dv_fb, 4);

                if abs(dv_fb) < min_step
                    dv_fb = min_step * sign(-freq_err);
                end

                v_fb = v_fb + dv_fb;
                v_fb = min(max(v_fb, v_min), v_max);
            end
        end

        % ---- 実際出す電圧（パルス中のみ ΔV 足す） -------------
        if phase == 1
            v_out = v_fb + DeltaV;
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

        % ---- ログ保存 -------------------------------------------
        time_log(end+1)  = t;       %#ok<AGROW>
        frfr_log(end+1)  = frfr_ns; %#ok<AGROW>
        ao1_log(end+1)   = v_out;   %#ok<AGROW>
        phase_log(end+1) = phase;   %#ok<AGROW>

        fprintf("t=%.1f s | phase=%d | FRFR=%.2f ns | freq_err=%.3f ns/s | ao1=%.4f V\n", ...
                t, phase, frfr_ns, freq_err, v_out);

        pause(fb_interval);
    end

    %% ---- CSV ログ保存 -------------------------------------------
    time_vec  = time_log(:);
    frfr_vec  = frfr_log(:);
    ao1_vec   = ao1_log(:);
    phase_vec = phase_log(:);

    log_tbl = table(time_vec, frfr_vec, ao1_vec, phase_vec, ...
        'VariableNames', {'time_s','frfr_ns','ao1_V','phase'});

    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    log_filename = sprintf('frfr_time_sweep_V%.2f_T%.3f_%s.csv', ...
                           DeltaV, Tpulse, timestamp);

    writetable(log_tbl, log_filename);
    fprintf("single_run: ログを保存しました → %s\n", log_filename);
end
