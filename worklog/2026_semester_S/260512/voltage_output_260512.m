function result = voltage_output_260512(ao0_V, ao1_V, hold_s)
%====================================================================
% 電圧出力ユーティリティ (2026-05-12 版)
%
% NI DAQ (Dev1) の ao0 / ao1 に指定電圧を出力し、指定秒数ホールド後
% 0V に戻して終了する。260428 版と同等。NI 接続テスト後の動作確認用。
%
% 使い方:
%   voltage_output_260512()                    % 既定値で実行 (0V, 0V, 5s)
%   voltage_output_260512(1.54, 1.64, 10)      % ao0=1.54V, ao1=1.64V, 10秒
%   voltage_output_260512(2.5, 2.5, 5)         % 両ch 中点 2.5V, 5秒
%
% 引数:
%   ao0_V  : ao0 出力電圧 [V] (0-5V) 既定 0
%   ao1_V  : ao1 出力電圧 [V] (0-5V) 既定 0
%   hold_s : 保持時間 [s]            既定 5
%
% 安全装置:
%   - 0-5V にクランプ
%   - onCleanup で異常終了時も 0V に戻して release
%====================================================================

    %% === 引数チェック =================================================
    if nargin < 1, ao0_V  = 0;  end
    if nargin < 2, ao1_V  = 0;  end
    if nargin < 3, hold_s = 5;  end

    v_min = 0; v_max = 5;
    ao0_V_clamped = min(max(ao0_V, v_min), v_max);
    ao1_V_clamped = min(max(ao1_V, v_min), v_max);

    if ao0_V_clamped ~= ao0_V
        warning("ao0 を %.3f V → %.3f V にクランプしました", ao0_V, ao0_V_clamped);
    end
    if ao1_V_clamped ~= ao1_V
        warning("ao1 を %.3f V → %.3f V にクランプしました", ao1_V, ao1_V_clamped);
    end

    %% === DAQ 初期化 ===================================================
    fprintf("=== DAQ 初期化中 ===\n");
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    c = onCleanup(@() cleanupDAQ(s)); %#ok<NASGU>

    %% === 電圧出力 =====================================================
    fprintf("出力: ao0 = %.3f V, ao1 = %.3f V (%.1f 秒保持)\n", ...
        ao0_V_clamped, ao1_V_clamped, hold_s);

    t_start = datetime('now');
    outputSingleScan(s, [ao0_V_clamped, ao1_V_clamped]);

    %% === 保持 =========================================================
    pause(hold_s);

    %% === 0V に戻す ====================================================
    outputSingleScan(s, [0, 0]);
    fprintf("出力終了: ao0 = 0 V, ao1 = 0 V\n");

    t_end = datetime('now');
    elapsed = seconds(t_end - t_start);

    %% === 結果 =========================================================
    result = struct( ...
        'ao0_V',     ao0_V_clamped, ...
        'ao1_V',     ao1_V_clamped, ...
        'hold_s',    hold_s, ...
        'elapsed_s', elapsed, ...
        't_start',   t_start, ...
        't_end',     t_end);

    fprintf("=== 完了（経過 %.2f 秒）===\n", elapsed);
end

function cleanupDAQ(s)
    % 異常終了時も含めて必ず 0V に戻して release
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
end
