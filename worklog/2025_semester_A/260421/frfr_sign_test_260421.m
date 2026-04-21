function result = frfr_sign_test_260421()
%====================================================================
% ゲイン符号確認テスト
%
% ao1 を 1.54V → 1.64V (+0.1V) にステップさせ、FRFR が
% 増加するか減少するかを確認する。
%
% 期待: K > 0 → FRFR が増加（約 8 ns/s の追加ドリフト）
%
% 手順:
%   1. ao0=1.54V, ao1=1.54V で 30秒計測（ベースライン）
%   2. ao1=1.64V にステップ、30秒計測
%   3. ao1=1.54V に戻す、30秒計測
%   4. ドリフトレートの変化から符号を判定
%
% 所要時間: 約 90秒
%====================================================================

    %% === DAQ / Scope 初期化 ==========================================
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@() cleanupDAQ(s, dev)); %#ok<NASGU>

    %% === パラメータ ====================================================
    Ts = 0.3;               % [s]
    ao0_const = 1.54;       % [V]
    ao1_base  = 1.54;       % [V] ベースライン
    ao1_step  = 1.64;       % [V] ステップ (+0.1V)
    t_phase   = 30;         % [s] 各フェーズの時間

    %% === ログ ==========================================================
    time_log = [];
    frfr_log = [];
    ao1_log  = [];
    phase_label = [];  % 1=baseline, 2=step, 3=recovery

    %% === 計測ループ ====================================================
    phases = [ao1_base, ao1_step, ao1_base];
    labels = [1, 2, 3];

    t_start = datetime('now');

    for p = 1:3
        ao1_now = phases(p);
        outputSingleScan(s, [ao0_const, ao1_now]);
        fprintf("Phase %d: ao1 = %.2f V\n", p, ao1_now);

        while true
            t = seconds(datetime('now') - t_start);
            if t > p * t_phase, break; end

            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                frfr_sec = str2double(readline(dev));
            catch ME
                warning("Read error: %s", ME.message);
                break;
            end
            raw_frfr = frfr_sec * 1e9;

            time_log(end+1)  = t;         %#ok<AGROW>
            frfr_log(end+1)  = raw_frfr;  %#ok<AGROW>
            ao1_log(end+1)   = ao1_now;   %#ok<AGROW>
            phase_label(end+1) = labels(p); %#ok<AGROW>

            fprintf("  t=%.1f | FRFR=%.2f ns | ao1=%.2f V\n", t, raw_frfr, ao1_now);
            pause(Ts);
        end
    end

    %% === 解析 ==========================================================
    % 各フェーズの wrapped delta からドリフトレートを推定
    fprintf("\n=== 符号判定結果 ===\n");
    for p = 1:3
        idx = phase_label == p;
        frfr_p = frfr_log(idx);
        if numel(frfr_p) < 3, continue; end

        % wrapped delta の中央値でドリフトレート推定
        deltas = diff(frfr_p);
        % wrap to [-50, 50]
        deltas = mod(deltas + 50, 100) - 50;
        drift_rate = median(deltas) / Ts;

        phase_names = {'Baseline', 'Step +0.1V', 'Recovery'};
        fprintf("  %s: FRFRdot ≈ %.2f ns/s\n", phase_names{p}, drift_rate);
    end

    fprintf("\n判定:\n");
    fprintf("  Step フェーズで FRFRdot が増加 → K > 0（ao1↑ で FRFR↑）\n");
    fprintf("  Step フェーズで FRFRdot が減少 → K < 0（ao1↑ で FRFR↓）\n");

    %% === CSV 保存 ======================================================
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    log_name = sprintf('frfr_sign_test_%s.csv', timestamp);

    log_tbl = table(time_log(:), frfr_log(:), ao1_log(:), phase_label(:), ...
        'VariableNames', {'time_s', 'frfr_raw_ns', 'ao1_V', 'phase'});
    writetable(log_tbl, log_name);
    fprintf("ログ保存: %s\n", log_name);

    result = struct('log_csv', log_name);
end

function cleanupDAQ(s, dev)
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
