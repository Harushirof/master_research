function cleanupDAQ(s, dev)
% cleanupDAQ
%   出力を 0V に戻し、DAQ セッションとオシロ接続を解放する。

    % 可能なら 0V を出す
    try
        if ~isempty(s.Channels)
            n = numel(s.Channels);
            outputSingleScan(s, zeros(1, n));
        end
    catch
        % ここでのエラーは無視
    end

    % DAQ 停止・解放
    try, stop(s);    end
    try, release(s); end

    % オシロのオブジェクトをクリア
    try, clear dev;  end

    fprintf("cleanupDAQ: ao を 0V に戻し、セッションを解放しました。\n");
end
