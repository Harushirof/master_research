function log_frfr_fixed_voltage_10s()

    % —————— NIデバイス設定 ——————
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, 'Dev1', 'ao0', 'Voltage');

    % —————— オシロ接続（例：SIGLENT SDS2204X HD） ——————
    ip  = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 5;

    % —————— 計測条件 ——————
    duration    = 10;       % 全体の計測時間 [秒]
    fb_interval = 0.2;      % サンプリング間隔 [秒]
    nPts        = floor(duration / fb_interval) + 1;

    % —————— ログ配列の初期化 ——————
    time = zeros(nPts,1);
    P1   = zeros(nPts,1);  % CH1 周波数
    P2   = zeros(nPts,1);  % CH2 周波数
    FRFR = zeros(nPts,1);  % 差分

    % —————— 電圧出力（10秒間 0.05V固定） ——————
    output_voltage = 0.05;

    fprintf("10秒間 0.05V 出力を続けながらFRFRをログ記録します...\n");

    % —————— 計測ループ ——————
    tStart = tic;
    for idx = 1:nPts
        elapsed = toc(tStart);
        time(idx) = elapsed;

        % 周波数取得（SCPI）
        try
            P1(idx) = str2double( dev.query(":MEASure:FREQuency? CHAN1") );
            P2(idx) = str2double( dev.query(":MEASure:FREQuency? CHAN2") );
        catch ME
            warning("SCPIエラー: %s", ME.message);
            P1(idx) = NaN;
            P2(idx) = NaN;
        end

        % FRFR計算（CH1 − CH2）
        FRFR(idx) = P1(idx) - P2(idx);

        % 電圧出力継続
        outputSingleScan(s, output_voltage);

        % 次サンプリングまで待つ
        pause( max(0, fb_interval - mod(toc(tStart), fb_interval)) );
    end

    % —————— 出力停止 ——————
    outputSingleScan(s, 0.0);
    release(s);
    clear dev;

    fprintf("測定完了。ログを保存します。\n");

    % —————— CSV保存 ——————
    T = table(time, P1, P2, FRFR);
    filename = sprintf("FRFR_Log_%s.csv", datestr(now,'yyyymmdd_HHMMSS'));
    writetable(T, filename);
    fprintf("ログを保存しました：%s\n", filename);

    % —————— プロット表示 ——————
    figure;
    plot(time, P1,   '-o', 'DisplayName', 'P1 (CH1周波数)'); hold on;
    plot(time, P2,   '-s', 'DisplayName', 'P2 (CH2周波数)');
    plot(time, FRFR, '-^', 'DisplayName', 'FRFR (CH1 - CH2)');
    xlabel("経過時間 [s]");
    ylabel("周波数 [Hz]");
    legend('Location', 'best');
    title("10秒間の周波数・差分ログ");
    grid on;

end

