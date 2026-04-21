function result = frfr_state_space_fb_2state_run(t_total, FRFR_ref)
%====================================================================
% 2状態FB（FRFR + FRFR微分）で位相同期を行う（ブログの「距離＋速度差」になぞらえる）
%
% 状態（相当）:
%   x1 = FRFR [ns]                （距離相当）
%   x2 = d/dt(FRFR) [ns/s]        （速度差相当）※数値微分＋平滑で推定
%
% 制御（2状態）:
%   u_cmd = u0 - k1*(FRFR - FRFR_ref) - k2*(FRFRdot_hat - 0)
%
% 重要（符号）:
%   「ao1を上げるとFRFRが増える」前提で符号を組んでいる。
%   もし逆なら、k1,k2 の符号を反転（または u_cmd の式の符号を反転）してください。
%
% 入出力:
%   result.log_csv : 保存ログCSV名
%   result.params  : 使用パラメータ
%
% ログCSV列:
%   time_s, frfr_ns, frfrdot_raw_nsps, frfrdot_hat_nsps, err_frfr_ns,
%   ao1_V, u_cmd_V, frfr_offset_ns
%====================================================================

    if nargin < 1 || isempty(t_total)
        t_total = 180; % [s]
    end
    if nargin < 2 || isempty(FRFR_ref)
        FRFR_ref = 25; % [ns] target（コード上で自由に変更可）
    end

    %% --- DAQ / Scope init ------------------------------------------
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % cleanup時に出す安全電圧（必要なら調整）
    SAFE_AO0_V = 0.0;
    SAFE_AO1_V = 0.0;
    c = onCleanup(@()cleanupDAQ(s, dev, SAFE_AO0_V, SAFE_AO1_V)); %#ok<NASGU>

    %% --- Parameters -------------------------------------------------
    Ts       = 0.3;      % [s] サンプリング
    ao0_const = 1.54;    % [V] 固定出力（あなたの系に合わせて）
    u0        = 1.54;    % [V] baseline
    v_min     = 0.0;
    v_max     = 5.0;

    % --- 2状態ゲイン（初期値：決め打ち） ----------------------------
    k1 = 0.002;          % [V/ns]    FRFR項
    k2 = 0.005;          % [V/(ns/s)] FRFR微分項（速度差相当）

    % --- FRFR微分 推定（指数平滑） -----------------------------------
    alpha = 0.2;         % (0,1]   小さいほど強く平滑
                         % 目安：有効時定数 ~ Ts/alpha

    % --- Safety: rate limit ------------------------------------------
    du_max = 0.02;       % [V] max |Δu| per step

    % --- Unwrap (あなたのロジックを踏襲) ------------------------------
    JUMP_DETECT_NS = 50; % [ns]
    OFFSET_STEP_NS = 100;% [ns]（1周相当とみなす値）

    %% --- Unwrap / Derivative states ---------------------------------
    prev_raw_frfr   = NaN;   % unwrap用
    frfr_offset     = 0;     % unwrap用 [ns]

    prev_frfr_corr  = NaN;   % 微分用（補正後FRFR）
    frfrdot_hat     = 0;     % 推定FRFR微分（平滑後）[ns/s]

    %% --- Logs --------------------------------------------------------
    time_log         = [];
    frfr_log         = [];
    frfrdot_raw_log  = [];
    frfrdot_hat_log  = [];
    err_frfr_log     = [];
    ao1_log          = [];
    ucmd_log         = [];
    offset_log       = [];

    %% --- Initial output ---------------------------------------------
    u_applied = clamp(u0, v_min, v_max);
    outputSingleScan(s, [ao0_const, u_applied]);

    %% --- Main loop ---------------------------------------------------
    t_start = datetime('now');

    while true
        t = seconds(datetime('now') - t_start);
        if t > t_total
            break;
        end

        % ---- FRFR read ----
        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_sec = str2double(readline(dev));
        catch ME
            warning("FRFR read error: %s", ME.message);
            break;
        end
        raw_frfr = frfr_sec * 1e9; % [ns]

        % ---- Unwrap ----
        if ~isnan(prev_raw_frfr)
            delta_raw = raw_frfr - prev_raw_frfr;
            if delta_raw <= -JUMP_DETECT_NS
                frfr_offset = frfr_offset + OFFSET_STEP_NS;
            elseif delta_raw >= +JUMP_DETECT_NS
                frfr_offset = frfr_offset - OFFSET_STEP_NS;
            end
        end
        frfr_corr = raw_frfr + frfr_offset; % [ns]
        prev_raw_frfr = raw_frfr;

        % ---- FRFR derivative (raw) ----
        if isnan(prev_frfr_corr)
            frfrdot_raw = 0;
        else
            frfrdot_raw = (frfr_corr - prev_frfr_corr) / Ts; % [ns/s]
        end
        prev_frfr_corr = frfr_corr;

        % ---- FRFR derivative (smoothed) ----
        frfrdot_hat = (1 - alpha) * frfrdot_hat + alpha * frfrdot_raw;

        % ---- Errors (2-state) ----
        e_frfr = frfr_corr - FRFR_ref;     % [ns]
        e_dot  = frfrdot_hat - 0;          % [ns/s] 目標=0

        % ---- 2-state FB (absolute command; NO integration) ----
        u_cmd = u0 - k1 * e_frfr - k2 * e_dot;
        u_cmd = clamp(u_cmd, v_min, v_max);

        % ---- Rate limit on applied voltage ----
        u_next = clamp(u_cmd, u_applied - du_max, u_applied + du_max);
        u_next = clamp(u_next, v_min, v_max);

        % ---- Output ----
        try
            outputSingleScan(s, [ao0_const, u_next]);
        catch ME
            warning("DAQ output error: %s", ME.message);
            break;
        end
        u_applied = u_next;

        % ---- Log ----
        time_log(end+1)        = t;            %#ok<AGROW>
        frfr_log(end+1)        = frfr_corr;    %#ok<AGROW>
        frfrdot_raw_log(end+1) = frfrdot_raw;  %#ok<AGROW>
        frfrdot_hat_log(end+1) = frfrdot_hat;  %#ok<AGROW>
        err_frfr_log(end+1)    = e_frfr;       %#ok<AGROW>
        ao1_log(end+1)         = u_applied;    %#ok<AGROW>
        ucmd_log(end+1)        = u_cmd;        %#ok<AGROW>
        offset_log(end+1)      = frfr_offset;  %#ok<AGROW>

        fprintf("t=%.1f s | FRFR=%.2f ns | FRFRdot=%.3f ns/s | e=%.2f ns | ao1=%.4f V | u_cmd=%.4f V\n", ...
                t, frfr_corr, frfrdot_hat, e_frfr, u_applied, u_cmd);

        pause(Ts);
    end

    %% --- Save CSV ----------------------------------------------------
    timestamp = datestr(now,'yyyymmdd_HHMMSS');
    log_name  = sprintf('frfr_statefb_2state_%s.csv', timestamp);

    log_tbl = table( ...
        time_log(:), frfr_log(:), frfrdot_raw_log(:), frfrdot_hat_log(:), err_frfr_log(:), ...
        ao1_log(:), ucmd_log(:), offset_log(:), ...
        'VariableNames', {'time_s','frfr_ns','frfrdot_raw_nsps','frfrdot_hat_nsps','err_frfr_ns', ...
                          'ao1_V','u_cmd_V','frfr_offset_ns'} );

    writetable(log_tbl, log_name);
    fprintf("Saved log: %s\n", log_name);

    %% --- Plots -------------------------------------------------------
    figure('Name','FRFR vs time','NumberTitle','off');
    plot(time_log, frfr_log, 'LineWidth', 2); grid on; hold on;
    yline(FRFR_ref, 'r--', sprintf('Target %.2f ns', FRFR_ref));
    xlabel('Time [s]'); ylabel('FRFR [ns]'); title('FRFR');

    figure('Name','FRFRdot vs time','NumberTitle','off');
    plot(time_log, frfrdot_hat_log, 'LineWidth', 2); grid on; hold on;
    yline(0, 'r--', 'Target 0 ns/s');
    xlabel('Time [s]'); ylabel('d(FRFR)/dt [ns/s]'); title('FRFR derivative (smoothed)');

    figure('Name','Control Voltage','NumberTitle','off');
    plot(time_log, ao1_log, 'LineWidth', 2); hold on;
    plot(time_log, ucmd_log, '--', 'LineWidth', 1.5);
    grid on;
    xlabel('Time [s]'); ylabel('ao1 [V]');
    legend('Applied','Commanded');
    title('Control Voltage');

    %% --- Return ------------------------------------------------------
    result = struct();
    result.log_csv = log_name;
    result.params = struct( ...
        'Ts', Ts, 't_total', t_total, 'FRFR_ref', FRFR_ref, ...
        'ao0_const', ao0_const, 'u0', u0, 'v_min', v_min, 'v_max', v_max, ...
        'k1', k1, 'k2', k2, 'alpha', alpha, ...
        'du_max', du_max, ...
        'JUMP_DETECT_NS', JUMP_DETECT_NS, 'OFFSET_STEP_NS', OFFSET_STEP_NS, ...
        'ip', ip );
end

function y = clamp(x, lo, hi)
    y = min(max(x, lo), hi);
end

function cleanupDAQ(s, dev, safe_ao0, safe_ao1)
% 例外が起きても、NI出力と通信を安全側に倒して終了する
    try
        outputSingleScan(s, [safe_ao0, safe_ao1]);
    catch
    end
    try
        release(s);
    catch
    end
    try
        clear dev;
    catch
    end
end
