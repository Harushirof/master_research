%動かず
% --- 初期設定 ---
osci = visa('NI', 'TCPIP0::192.168.1.100::INSTR');
fopen(osci);

daqSession = daq.createSession('ni');
addAnalogOutputChannel(daqSession, 'Dev1', 'ao0', 'Voltage');

% パラメータ設定
Ki = 0.0001;               % 積分ゲイン（非常に小さく）
dt = 0.5;                  % 制御周期
integral = 0;
V_max = 5;
V_min = 0;
integral_max = 1e6;        % 積分値の制限（風袋防止）
deadband = 100;           % ノイズ抑制のためのデッドバンド（±100Hz以下の誤差は無視）

% ログ用
log_time = [];
log_error = [];
log_voltage = [];

% 制御開始
disp('I制御（高ボラ対応）開始...');
tic;
last_voltage = 0;
while toc < 300
    % 周波数取得
    fprintf(osci, ':MEASure:FREQuency? CH1');
    f1 = str2double(fscanf(osci));

    fprintf(osci, ':MEASure:FREQuency? CH2');
    f2 = str2double(fscanf(osci));

    error = f1 - f2;

    % デッドバンド処理
    if abs(error) > deadband
        integral = integral + error * dt;
        integral = min(max(integral, -integral_max), integral_max);
    end

    % 制御電圧
    control_voltage = Ki * integral;
    control_voltage = min(max(control_voltage, V_min), V_max);

    % スルーレート制限（急激な変化抑制）
    max_delta = 0.1;  % 電圧変化の最大許容（V）
    delta_v = control_voltage - last_voltage;
    if abs(delta_v) > max_delta
        control_voltage = last_voltage + sign(delta_v) * max_delta;
    end
    last_voltage = control_voltage;

    % DAQ出力
    outputSingleScan(daqSession, control_voltage);

    % ログ
    log_time(end+1) = toc;
    log_error(end+1) = error;
    log_voltage(end+1) = control_voltage;

    fprintf('t=%.1fs | f1=%.1f | f2=%.1f | err=%.1f | V=%.3f\n', ...
        toc, f1, f2, error, control_voltage);

    pause(dt);
end

outputSingleScan(daqSession, 0);  % 安全措置
fclose(osci);
delete(osci);
clear osci;

disp('制御終了');

% ログ描画
figure;
subplot(2,1,1);
plot(log_time, log_error);
ylabel('Freq Error [Hz]');
title('I制御（高ボラ）ログ');

subplot(2,1,2);
plot(log_time, log_voltage);
ylabel('Control Voltage [V]');
xlabel('Time [s]');
