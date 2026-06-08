function result = scope_response_test_260512_visual(hold_s, ao1_test_V)
%====================================================================
% オシロ応答確認テスト (2026-05-12) — 目視版（VISA 不要）
%
% 目的:
%   PC からの電圧出力が OCXO に反映されているかをオシロ画面で目視確認。
%   VISA でオシロを読まないので、オシロが LAN で見えない状態でも実行可能。
%
% 手順:
%   Phase 1 (5秒)  : ao0=1.54V, ao1=1.54V — ベースライン
%   Phase 2 (hold_s秒): ao0=1.54V, ao1=3.0V — テスト電圧
%   Phase 3 (5秒)  : ao0=1.54V, ao1=1.54V — 復帰
%
% 期待:
%   K = +80.9 ns/(V·s)
%   Phase 2 で FRFRdot ≈ +118 ns/s — オシロ画面で CH2 が速く流れる
%
% 引数:
%   hold_s     : Phase 2 保持時間 [s]   既定 30
%   ao1_test_V : ao1 テスト電圧 [V]     既定 3.0
%====================================================================

    if nargin < 1 || isempty(hold_s),     hold_s     = 30;  end
    if nargin < 2 || isempty(ao1_test_V), ao1_test_V = 3.0; end

    v_min = 0; v_max = 5;
    ao0_const  = 1.54;
    ao1_test_V = min(max(ao1_test_V, v_min), v_max);

    %% === DAQ 初期化 ===================================================
    fprintf("=== オシロ応答確認テスト（目視版）===\n");
    fprintf("ao0 = %.3f V（固定, OCXO-A 平衡点）\n", ao0_const);
    fprintf("ao1 = %.3f V（テスト, %.1f 秒保持）\n", ao1_test_V, hold_s);
    fprintf("期待ドリフト: FRFRdot ≈ %.1f ns/s\n\n", 80.9 * (ao1_test_V - 1.54));

    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    c = onCleanup(@() cleanupDAQ(s)); %#ok<NASGU>

    %% === Phase 1: ベースライン（5秒）=================================
    fprintf("--- Phase 1: ベースライン ao1=1.54V (5秒) ---\n");
    fprintf("オシロを見て CH2 のドリフト速度を覚えておく\n");
    outputSingleScan(s, [ao0_const, 1.54]);
    countdown(5);

    %% === Phase 2: テスト電圧 =========================================
    fprintf("\n--- Phase 2: ao1 = %.3f V (%.0f秒) ---\n", ao1_test_V, hold_s);
    fprintf("ドリフトが速くなれば PC 出力は反映されている\n");
    outputSingleScan(s, [ao0_const, ao1_test_V]);
    t_start = datetime('now');
    countdown(hold_s);

    %% === Phase 3: ベースラインに戻して確認 ==========================
    fprintf("\n--- Phase 3: ao1=1.54V に戻す (5秒) ---\n");
    fprintf("ドリフトが元の速度に戻れば確実\n");
    outputSingleScan(s, [ao0_const, 1.54]);
    countdown(5);

    %% === 終了処理 =====================================================
    outputSingleScan(s, [0, 0]);
    t_end = datetime('now');
    fprintf("\n=== 終了: ao0=0V, ao1=0V ===\n");

    result = struct( ...
        'ao0_V',     ao0_const, ...
        'ao1_test_V', ao1_test_V, ...
        'hold_s',    hold_s, ...
        'expected_FRFRdot_ns_per_s', 80.9 * (ao1_test_V - 1.54), ...
        't_start',   t_start, ...
        't_end',     t_end);
end

function countdown(sec)
    n = floor(sec / 5);
    rem_s = sec - n * 5;
    for i = 1:n
        pause(5);
        fprintf("  残り %d 秒\n", sec - i * 5);
    end
    if rem_s > 0, pause(rem_s); end
end

function cleanupDAQ(s)
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
end
