function realtime_ocxo_Icontrol_with_plot
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % 実機に合わせて

    % --- 制御パラメータ ---
    Ts = 0.05;                    % 制御周期 [秒]
    Ki = 1e-6;                    % 積分ゲイン [V/Hz/s]
    Vctrl = 2.5;                  % 初期制御電圧
    integral = 0;
    integral_limit = 1e6;
    Vmax = 5; Vmin = 0;
    deadband = 300;              % デッドバンド [Hz]
    max_dV = 0.1;

    % オシロスコープ接続
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    % --- ログ初期化 ---
    time_log = [];
    df_log = [];
    vctrl_log = [];

    % --- グラフ初期化 ---
    figure('Name', 'OCXO I制御リアルタイムプロット');
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

    fprintf("=== OCXO I制御（グラフ付き）開始 ===\n");
    t0 = tic;

    while ishandle(h1)
        t_now = toc(t0);

        % 周波数差取得
        df = readDeltaF(dev);

        % デッドバンド処理
        if abs(df) > deadband
            integral = integral + df * Ts;
            integral = min(max(integral, -integral_limit), integral_limit);
        end

        % 制御電圧更新
        dV = Ki * integral;
        Vctrl = Vctrl + dV;
        Vctrl = min(max(Vctrl, Vmin), Vmax);

        % 出力
        write(d, Vctrl);

        % ログ更新
        time_log(end+1) = t_now;
        df_log(end+1) = df;
        vctrl_log(end+1) = Vctrl;

        % グラフ更新
        set(h1, 'XData', time_log, 'YData', df_log);
        set(h2, 'XData', time_log, 'YData', vctrl_log);
        xlim(ax1, [max(0, t_now-30), t_now]);  % 直近30秒を表示
        xlim(ax2, [max(0, t_now-30), t_now]);
        drawnow limitrate;

        % 状況表示
        fprintf("t = %.1fs | Δf = %+8.2f Hz | Vctrl = %.3f V\n", t_now, df, Vctrl);

        pause(Ts);
    end
end

function df = readDeltaF(dev)
    % 周波数差取得
    writeline(dev, ":MEAS:ADV:P1:VAL?");
    f1 = str2double(readline(dev));
    writeline(dev, ":MEAS:ADV:P2:VAL?");
    f2 = str2double(readline(dev));
    df = f1 - f2;
end

