function result = scope_response_test_260512(hold_s, ao1_test_V)
%====================================================================
% オシロ応答確認テスト (2026-05-12) — FRFR ロギング版
%
% 目的:
%   「PC からの電圧出力が OCXO に反映されているか」を
%   オシロから FRFR を VISA で読み、CSV に保存して数値判定する。
%
% 手順:
%   Phase 1 (5秒)  : ao0=1.54V, ao1=1.54V — ベースラインドリフト
%   Phase 2 (hold_s秒): ao0=1.54V, ao1=3.0V — テスト電圧
%   Phase 3 (5秒)  : ao0=1.54V, ao1=1.54V — 復帰
%
% 期待:
%   K = +80.9 ns/(V·s)
%   Phase 1 ドリフト ≈ 0 ns/s（平衡）
%   Phase 2 ドリフト 
% ≈ +118 ns/s（ao1=3V → +1.46V → 80.9*1.46）
%   Phase 3 ドリフト ≈ 0 ns/s
%
% 判定:
%   |Phase2 ドリフト - Phase1 ドリフト| > 30 ns/s なら「反映 OK」
%   差が小さければ PC 出力が反映されていない
%
% 引数:
%   hold_s     : Phase 2 保持時間 [s]   既定 30
%   ao1_test_V : ao1 テスト電圧 [V]     既定 3.0
%
% 出力:
%   result.log_csv : 保存した CSV ファイル名
%   result.summary : 各 Phase のドリフトレート [ns/s]
%   result.verdict : '反映 OK' or '反映されていない疑い'
%====================================================================

    if nargin < 1 || isempty(hold_s),     hold_s     = 30;  end
    if nargin < 2 || isempty(ao1_test_V), ao1_test_V = 3.0; end

    % 0-5V クランプ
    v_min = 0; v_max = 5;
    ao0_const  = 1.54;
    ao1_base   = 1.54;
    ao1_test_V = min(max(ao1_test_V, v_min), v_max);

    Ts = 0.3;  % [s] サンプリング周期

    %% === DAQ / Scope 初期化 ==========================================
    fprintf("=== オシロ応答確認テスト (FRFR ロギング版) ===\n");
    fprintf("ao0 = %.3f V（固定）\n", ao0_const);
    fprintf("ao1 ベース = %.3f V, テスト = %.3f V\n", ao1_base, ao1_test_V);
    fprintf("期待 Phase2 ドリフト: ≈ %.1f ns/s\n\n", 80.9 * (ao1_test_V - 1.54));

    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@() cleanupDAQ(s, dev)); %#ok<NASGU>

    %% === ログ用配列 ===================================================
    time_log    = [];
    frfr_log    = [];
    ao1_log     = [];
    phase_log   = [];   % 1=baseline, 2=test, 3=recovery

    %% === 3 Phase 実行 =================================================
    phases = [ao1_base, ao1_test_V, ao1_base];
    durations = [5, hold_s, 5];
    phase_names = {'Baseline', sprintf('Test %.2fV', ao1_test_V), 'Recovery'};

    t_start = datetime('now');

    for p = 1:3
        ao1_now = phases(p);
        outputSingleScan(s, [ao0_const, ao1_now]);
        fprintf("--- Phase %d (%s): ao1 = %.3f V (%.0f秒) ---\n", ...
            p, phase_names{p}, ao1_now, durations(p));

        % この phase の終了時刻（累計秒）
        t_phase_end = sum(durations(1:p));

        while true
            t = seconds(datetime('now') - t_start);
            if t > t_phase_end, break; end

            % FRFR を VISA で読む
            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                frfr_sec = str2double(readline(dev));
                raw_frfr = frfr_sec * 1e9;  % [ns]
            catch ME
                warning("VISA 読み取りエラー: %s", ME.message);
                raw_frfr = NaN;
            end

            time_log(end+1)  = t;       %#ok<AGROW>
            frfr_log(end+1)  = raw_frfr;%#ok<AGROW>
            ao1_log(end+1)   = ao1_now; %#ok<AGROW>
            phase_log(end+1) = p;       %#ok<AGROW>

            fprintf("  t=%6.2f | FRFR=%8.2f ns | ao1=%.3f V\n", ...
                t, raw_frfr, ao1_now);
            pause(Ts);
        end
    end

    %% === 後始末 =======================================================
    outputSingleScan(s, [0, 0]);
    fprintf("\n=== 出力終了: ao0=0V, ao1=0V ===\n");

    %% === 解析: 各 Phase のドリフトレート ============================
    fprintf("\n=== 解析結果 ===\n");
    drift_rates = nan(1, 3);
    for p = 1:3
        idx = phase_log == p;
        frfr_p = frfr_log(idx);
        if numel(frfr_p) < 3, continue; end

        % wrapped delta（FRFR は 0-100ns で周期的にラップ）
        deltas = diff(frfr_p);
        deltas = mod(deltas + 50, 100) - 50;  % [-50, 50] にラップ
        drift_rates(p) = median(deltas) / Ts;

        fprintf("  Phase %d (%s): FRFRdot = %+7.2f ns/s (N=%d)\n", ...
            p, phase_names{p}, drift_rates(p), numel(frfr_p));
    end

    %% === 判定 =========================================================
    diff_drift = drift_rates(2) - drift_rates(1);
    THRESHOLD  = 30;  % [ns/s]
    if abs(diff_drift) > THRESHOLD
        verdict = '反映 OK';
        fprintf("\n判定: %s (Phase2-1 ドリフト差 = %+.2f ns/s > %.0f)\n", ...
            verdict, diff_drift, THRESHOLD);
    else
        verdict = '反映されていない疑い';
        fprintf("\n判定: %s (Phase2-1 ドリフト差 = %+.2f ns/s, 閾値 %.0f)\n", ...
            verdict, diff_drift, THRESHOLD);
    end

    %% === CSV 保存 =====================================================
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    log_name = sprintf('scope_response_%s.csv', timestamp);

    log_tbl = table(time_log(:), frfr_log(:), ao1_log(:), phase_log(:), ...
        'VariableNames', {'time_s', 'frfr_raw_ns', 'ao1_V', 'phase'});
    writetable(log_tbl, log_name);
    fprintf("\nログ保存: %s\n", log_name);

    %% === 戻り値 =======================================================
    result = struct( ...
        'log_csv',  log_name, ...
        'ao0_V',    ao0_const, ...
        'ao1_base', ao1_base, ...
        'ao1_test_V', ao1_test_V, ...
        'hold_s',   hold_s, ...
        'drift_phase1', drift_rates(1), ...
        'drift_phase2', drift_rates(2), ...
        'drift_phase3', drift_rates(3), ...
        'diff_drift',   diff_drift, ...
        'verdict',  verdict);
end

function cleanupDAQ(s, dev)
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
