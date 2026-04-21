% --- 初期設定 ---
osci = visa('NI', 'TCPIP0::192.168.1.61::inst0::INSTR');
fopen(osci);  % ← visadevではなく、fopenを使う従来の方法

% NI DAQ セッション
daqSession = daq.createSession('ni');
addAnalogOutputChannel(daqSession, 'Dev1', 'ao0', 'Voltage');

% 制御パラメータ設定
Ki = 0.00005;             % 積分ゲイン（調整必要）
dt = 0.5;                 % 制御周期 [秒]
integral = 0;             % 積分初期値
V_max = 5;                % 出力電圧上限
V_min = 0;                % 出力電圧下限
integral_max = 1e6;       % 積分値上限
deadband = 100;           % デッドバンド（誤差が小さいとき積分しない）
max_delta = 0.1;          % スルーレート制限（1ステップあたりの最大変化）

% ログ用変数
log_time = [];
log_error = [];
log_voltage = [];

disp('I制御（visa版）を開始します...');
tic;
last_voltage = 0;

% 制御ループ
while toc < 300  % 5分間
    try
        fprintf(osci, ':MEASure:FREQuency? CHAN1');  % 注意: CH1 → CHAN1 に変更
        f1 = str2double(fscanf(osci));
        
        fprintf(osci, ':MEASure:FREQuency? CHAN2');  % 同上
        f2 = str2double(fscanf(osci));
    catch
        warning("オシロスコープとの通信エラー");
        continue;
    end
    
    error = f1 - f2;
    
    % デッドバンド
    if abs(error) > deadband
        integral = integral + error * dt;
        integral = min(max(integral, -integral_max), integral_max);
    end
    
    % 制御電圧の計算
    control_voltage = Ki * integral;
    control_voltage = min(max(control_voltage, V_min), V_max);
    
    % スルーレート制限
    delta_v = control_voltage - last_voltage;
    if abs(delta_v) > max_delta
        control_voltage = last_voltage + sign(delta_v) * max_delta;
    end
    last_voltage = control_voltage;

    % DAQに電圧出力
    outputSingleScan(daqSession, control_voltage);

    % ログ記録
    log_time(end+1) = toc;
    log_error(end+1) = error;
    log_voltage(end+1) = control_voltage;

    fprintf('t=%.1fs | f1=%.1fHz | f2=%.1fHz | err=%.1fHz | V=%.3fV\n', ...
        toc, f1, f2, error, control_voltage);

    pause(dt);
end

% 終了処理
outputSingleScan(daqSession, 0);
fclose(osci);
delete(osci);
clear osci;
disp('I制御終了');

% 結果プロット
figure;
subplot(2,1,1);
plot(log_time, log_error);
ylabel('周波数誤差 [Hz]');
title('I制御ログ');

subplot(2,1,2);
plot(log_time, log_voltage);
ylabel('制御電圧 [V]');
xlabel('時間 [s]');
