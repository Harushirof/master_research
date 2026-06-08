function scope_constant_ao1_260512(ao1_V, duration_s)
%====================================================================
% 定電圧出力 + FRFR モニタ (2026-05-12)
%
% 目的:
%   ao1 を指定した一定電圧で出力しつづけ、FRFR の挙動を眺める。
%   周波数差が大きすぎて FRFR がばらつくときに、適切な電圧を
%   手探りで探すための簡易ツール。
%
% 使い方:
%   scope_constant_ao1_260512(1.0)        % ao1=1V, 既定30秒
%   scope_constant_ao1_260512(1.0, 60)    % ao1=1V, 60秒
%   Ctrl+C で中断 → onCleanup で ao0=0V, ao1=0V に戻す
%
% 引数:
%   ao1_V      : ao1 に出す電圧 [V]      既定 1.0
%   duration_s : モニタ時間 [s]          既定 30
%====================================================================

    if nargin < 1 || isempty(ao1_V),       ao1_V      = 1.0; end
    if nargin < 2 || isempty(duration_s),  duration_s = 30;  end

    v_min = 0; v_max = 5;
    ao0_const = 1.54;
    ao1_V     = min(max(ao1_V, v_min), v_max);

    Ts = 0.3;

    fprintf("=== 定電圧出力モニタ ===\n");
    fprintf("ao0 = %.3f V (固定), ao1 = %.3f V, %.0f秒\n\n", ...
        ao0_const, ao1_V, duration_s);

    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');
    addAnalogOutputChannel(s, 'Dev1', 'ao1', 'Voltage');

    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    c = onCleanup(@() cleanupDAQ(s, dev)); %#ok<NASGU>

    outputSingleScan(s, [ao0_const, ao1_V]);

    t_start = datetime('now');
    while true
        t = seconds(datetime('now') - t_start);
        if t > duration_s, break; end

        try
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr_ns = str2double(readline(dev)) * 1e9;
        catch ME
            warning("VISA 読み取りエラー: %s", ME.message);
            frfr_ns = NaN;
        end

        fprintf("  t=%6.2f | FRFR=%8.2f ns | ao1=%.3f V\n", ...
            t, frfr_ns, ao1_V);
        pause(Ts);
    end

    fprintf("\n=== 終了: ao0=0V, ao1=0V に戻します ===\n");
end

function cleanupDAQ(s, dev)
    try, outputSingleScan(s, [0, 0]); catch, end
    try, release(s); catch, end
    try, clear dev; catch, end
end
