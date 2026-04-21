function get_ch1_ch2_frfr_1000()

    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    nSamples = 1000;
    results = nan(nSamples, 4); % 時刻、CH1、CH2、FRFR

    disp("CH1, CH2, FRFR を1000回 0.1秒間隔で取得します...");

    for k = 1:nSamples
        try
            % 現在時刻（相対秒）を記録
            timestamp = datetime('now','Format','HH:mm:ss.SSS');

            % CH1 周波数 (P1)
            writeline(dev, "MEAS:ADV:P1:VAL?");
            f1 = str2double(readline(dev));

            % CH2 周波数 (P2)
            writeline(dev, "MEAS:ADV:P2:VAL?");
            f2 = str2double(readline(dev));

            % FRFR (P3)
            writeline(dev, "MEAS:ADV:P3:VAL?");
            frfr = str2double(readline(dev));

            % 結果保存
            results(k,:) = [posixtime(timestamp), f1, f2, frfr];

            % 任意で途中経過表示
            if mod(k, 100) == 0
                fprintf("%d回取得完了\n", k);
            end

            pause(0.1);

        catch ME
            warning("エラー: %s", ME.message);
        end
    end

    % セル配列でヘッダー付き保存
    filename = sprintf("CH1_CH2_FRFR_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    header = {'Time(s)','CH1_Hz','CH2_Hz','FRFR'};
    output_cell = [header; num2cell(results)];
    writecell(output_cell, filename);

    fprintf("結果を %s に保存しました。\n", filename);
    clear dev;
end
