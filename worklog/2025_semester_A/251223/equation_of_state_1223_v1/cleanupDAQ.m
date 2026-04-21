function cleanupDAQ(s, dev)
% cleanupDAQ  DAQとオシロを安全にクローズし、電圧を0Vに戻す
    try
        % 0V 出力（チャネル数が合うときのみ）
        if ~isempty(s.Channels)
            n = numel(s.Channels);
            outputSingleScan(s, zeros(1,n));
        end
    catch
        % ここでのエラーは無視
    end

    try
        stop(s);
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

    fprintf("cleanupDAQ: all outputs set to 0V and session released.\n");
end
