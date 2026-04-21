function test_fb_interval()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 電圧設定
    voltage = 2.94; % 予備実験の安定電圧
    outputSingleScan(s, voltage);

    % テストパラメータ
    intervals = [0.01, 0.05, 0.1, 0.2, 0.5]; % テストする間隔[秒]
    nSamples = 100; % 各間隔ごとの測定回数

    fprintf("FB間隔テスト開始：各間隔でFRFRの挙動を観察します\n");

    for dt = intervals
        fprintf("\n--- %.3f秒間隔テスト開始 ---\n", dt);
        frfr_vals = nan(nSamples, 1);

        for k = 1:nSamples
            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                frfr = str2double(readline(dev));
                frfr_vals(k) = frfr;

                pause(dt);

            catch
                warning("取得エラー");
            end
        end

        % 結果表示
        fprintf("間隔 %.3f秒：FRFR 平均=%.2f ns | ボラ=%.2f ns\n", ...
                dt, mean(frfr_vals, 'omitnan'), std(frfr_vals, 'omitnan'));

        % ヒストグラムプロット
        figure;
        histogram(frfr_vals, 50, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'black');
        title(sprintf("FRFRヒストグラム - 間隔 %.3f秒", dt));
        xlabel('FRFR [ns]');
        ylabel('出現回数');
        grid on;
    end

    outputSingleScan(s, 0); % 電圧リセット
    release(s);
    clear dev;

end
