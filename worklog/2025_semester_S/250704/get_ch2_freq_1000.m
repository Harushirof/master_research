function get_ch2_freq_1000()

    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    slot_ch2 = 2; % CH2のFREQが割り当てられているスロット（例：P2）

    nSamples = 1000;
    freq_ch2 = nan(nSamples, 1); % 結果保存用

    disp("CH2の周波数を1000回取得します（0.1秒間隔）...");

    for k = 1:nSamples
        try
            writeline(dev, sprintf("MEAS:ADV:P%d:VAL?", slot_ch2));
            resp = readline(dev);
            f2 = str2double(resp);
            freq_ch2(k) = f2;

            % 任意で途中経過表示
            if mod(k, 100) == 0
                fprintf("%d回取得完了\n", k);
            end

            pause(0.1); % 取得間隔 0.1秒

        catch ME
            warning("エラー: %s", ME.message);
            freq_ch2(k) = NaN;
        end
    end

    disp("取得完了、最初の10件を表示:");
    disp(freq_ch2(1:10));

    % 結果をCSV保存
    filename = sprintf("CH2_freq_%s.csv", datestr(now, 'yyyymmdd_HHMMSS'));
    writematrix(freq_ch2, filename);
    fprintf("結果を %s に保存しました。\n", filename);

    clear dev;

end
