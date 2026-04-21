function cleanupDAQ(s, dev)
% DAQ・オシロの後始末

    try
        stop(s);
    catch
    end

    try
        outputSingleScan(s, [0, 0]);
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
