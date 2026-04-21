function realtime_ocxo_Icontrol_feedback
    % --- NI DAQ 設定 ---
    d = daq("ni");
    addoutput(d, "Dev1", "ao0", "Voltage");  % 実機に合わせて変更

    % --- パラメータ設定 ---
    Ts = 0.05;                     % 制御周期 [秒]
    Ki = 1e-6;                     % 積分ゲイン [V/Hz/s]
    Vctrl = 2.5;                   % 初期電圧（中央値）
    integral = 0;                 % 積分項
    integral_limit = 1e6;         % 積分風袋防止
    Vmax = 5; Vmin = 0;           % 出力範囲
    max_dV = 0.1;                 % スルーレート制限
    deadband = 300;               % デッドバンド（Hz）

    % オシロ設定
    ip = "192.168.1.61";
    dev = visadev("TCPIP0::" + ip + "::inst0::INSTR");
    dev.Timeout = 10;
    writeline(dev, ":RUN");
    writeline(dev, ":MEAS:ADV:P1:TYPE FREQuency,CHAN1");
    writeline(dev, ":MEAS:ADV:P2:TYPE FREQuency,CHAN2");

    fprintf("=== I制御（フィードバック式）開始 ===\n");

    while true
        % Δf取得（f1:基準, f2:制御対象）
        df = readDeltaF(dev);

        % デッドバンド外の誤差のみ積分
        if abs(df) > deadband
            integral = integral + df * Ts;
            integral = min(max(integral, -integral_limit), integral_limit);
        end

        % 電圧フィードバック更新
        dV = Ki * integral;
        Vctrl = Vctrl + dV;

        % スルーレート制限
        dV_actual = Vctrl - writeLast(d, []);
        if abs(dV_actual) > max_dV
            Vctrl = writeLast(d, []) + sign(dV_actual) * max_dV;
        end

        % 電圧クリップ
        Vctrl = min(max(Vctrl, Vmin), Vmax);

        % 出力
        write(d, Vctrl);
        writeLast(d, Vctrl);  % 状態保持

        % ログ表示
        fprintf("Δf = %+8.2f Hz | ∫Δf = %+9.1f | Vctrl = %.3f V\n", df, integral, Vctrl);

        pause(Ts);
    end
end

% 周波数差（CH1 - CH2）
function df = readDeltaF(dev)
    writeline(dev, ":MEAS:ADV:P1:VAL?");
    f1 = str2double(readline(dev));
    writeline(dev, ":MEAS:ADV:P2:VAL?");
    f2 = str2double(readline(dev));
    df = f1 - f2;
end

% 電圧状態を保持する（スルーレート制限用）
function v = writeLast(~, newval)
    persistent last_v;
    if nargin == 2 && ~isempty(newval)
        last_v = newval;
    end
    if isempty(last_v)
        last_v = 2.5;
    end
    v = last_v;
end

