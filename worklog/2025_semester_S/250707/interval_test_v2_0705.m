function test_fb_interval_with_csv()

    % NI設定
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % オシロ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % 安定電圧設定
    voltage = 2.94;
    outputSingleScan(s, voltage);

    % テスト間隔一覧（必要なら追加・変更可）
    intervals = [0.01, 0.05, 0.1, 0.2, 0.5]; % [秒]
    nSamples = 100;

    % 結果保存先
    results_all = [];

    fprintf("FB間隔テスト（FRFR応答観察・CSV出力付き）開始\n");

    for dt = intervals
        fprintf("\n--- 間隔 %.3f 秒 テスト開始 ---\n", dt);
        frfr_vals = nan(nSamples, 1);
        timestamps = nan(nSamples, 1);

        for k = 1:nSamples
            try
                writeline(dev, "MEAS:ADV:P3:VAL?");
                frfr = str2double(readline(dev));
                t = posixtime(datetime('now'));

                frfr_vals(k) = frfr;
                timestamps(k) = t;

                pause(dt);

            catch
                warning("取得エラー");
            end
        end

        % 結果を統合保存：列順 → 間隔, 時刻, FRFR
        dt_col = dt * ones(nSamples, 1);
        results_all = [results_all; [dt_col, timestamps, frfr_vals]];

        % ヒストグラム表示（任意）
        figure;
        histogram(frfr_vals, 50, 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'black');
        title(sprintf("FRFR ヒストグラム - 間隔 %.3f秒", dt));
        xlabel('FRFR [ns]');
        ylabel('出現回数');
        grid on;

        % 簡易統計表示
        fprintf("間隔 %.3f 秒：平均 %.2f ns | ボラ %.2f ns\n", dt, mean(frfr_vals,'omitnan'), std(frfr_vals,'omitnan'));
    end

    outputSingleScan(s, 0); % 電圧リセット
    release(s);
    clear dev;

    % CSV出力（解析用）
    filename = sprintf("FRFR_intervalTest_20250705_%s.csv", datestr(now,'HHMMSS'));
    header = {'Interval_s','Time_s','FRFR_ns'};
    output_cell = [header; num2cell(results_all)];
    writecell(output_cell, filename);

    fprintf("\n全データを %s に保存しました。\n", filename);

end
