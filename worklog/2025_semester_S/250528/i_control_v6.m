%結構いい感じ
%時間平均2s

function realtime_ocxo_Icontrol_smoothed
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % 実機に合わせて

    % --- 制御パラメータ ---
    Ts = 0.05;                    % 制御周期 [秒]
    Ki = 1e-6;                    % 積分ゲイン [V/Hz/s]
    Voffset = 2.5;                % 電圧の中心値（初期出力）
    Vctrl = Voffset;             % 初期制御電圧
    integral = 0;
    integral_limit = 1e6;
    Vmax = 5; Vmin = 0;
    deadband = 500;              % [Hz]
    max_dV = 0.1;                % スルーレート制限

    % Δfの移動平均ウィンドウ
    avg_window_sec = 2.0;        % 2秒の移動平均
    N = round(avg_window_sec / Ts);
    df_buf = nan(1, N);

    % --- オシロスコープ接続 ---
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    % --- グラフ用ログ変数 ---
    time_log = [];
    df_log = [];
    vctrl_log = [];

    % --- グラフ初期化 ---
    figure('Name', 'OCXO I制御（平滑化付き）');
    ax1 = subplot(2,1,1);
    h1 = plot(ax1, NaN, NaN, 'b');
    ylabel(ax1, 'Δf [Hz]');
    title(ax1, '周波数差（CH1 - CH2）');

    ax2 = subplot(2,1,2);
    h2 = plot(ax2, NaN, NaN, 'r');
    ylabel(ax2, '制御電圧 [V]');
    xlabel(ax2, '時間 [s]');
    title(ax2, '出力電圧');

    drawnow;
    t0 = tic;

    fprintf("=== OCXO I制御（平滑化あり）開始 ===\n");

    % --- 制御ループ ---
    while ishandle(h1)
        t_now = toc(t0);

        % Δf取得
        df = readDeltaF(dev);

        % Δfの移動平均更新
        df_buf = [df_buf(2:end), df];
        df_avg = mean(df_buf, 'omitnan');

        % 積分処理（デッドバンド考慮）
        if abs(df_avg) > deadband
            integral = integral + df_avg * Ts;
            integral = min(max(integral, -integral_limit), integral_limit);
        end

        % 制御電圧更新（FB型）
        Vctrl_new = Voffset + Ki * integral;

        % スルーレート制限
        dV = Vctrl_new - Vctrl;
        if abs(dV) > max_dV
            Vctrl_new = Vctrl + sign(dV) * max_dV;
        end
        Vctrl = min(max(Vctrl_new, Vmin), Vmax);

        % DAQ出力
        write(d, Vctrl);

        % ログ更新
        time_log(end+1) = t_now;
        df_log(end+1) = df_avg;
        vctrl_log(end+1) = Vctrl;

        % プロット更新
        set(h1, 'XData', time_log, 'YData', df_log);
        set(h2, 'XData', time_log, 'YData', vctrl_log);
        xlim(ax1, [max(0, t_now - 30), t_now]);
        xlim(ax2, [max(0, t_now - 30), t_now]);
        drawnow limitrate;

        % モニタ出力
        fprintf("t = %.1fs | Δf_avg = %+8.2f Hz | Vctrl = %.3f V\n", ...
            t_now, df_avg, Vctrl);

        pause(Ts);
    end
end

function df = readDeltaF(dev)
    writeline(dev, ":MEAS:ADV:P1:VAL?");
    f1 = str2double(readline(dev));
    writeline(dev, ":MEAS:ADV:P2:VAL?");
    f2 = str2double(readline(dev));
    df = f1 - f2;
end
