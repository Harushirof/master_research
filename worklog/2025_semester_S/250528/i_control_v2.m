%visadev
% --- 初期設定 ---
% visadev による通信確立（IPとinst番号は確認済みのものを使用）
osci = visadev("TCPIP0::192.168.1.61::inst0::INSTR");

% NI DAQ セッション
daqSession = daq.createSession('ni');
addAnalogOutputChannel(daqSession, 'Dev1', 'ao0', 'Voltage');

% パラメータ設定
Ki = 0.00005;            % 積分ゲイン（小さくしておく）
dt = 0.5;                % 制御周期 [秒]
integral = 0;            % 積分初期値
V_max = 5;               % 電圧最大 [V]
V_min = 0;               % 電圧最小 [V]
integral_max = 1e6;      % 積分値の制限（風袋防止）
deadband = 100;          % ±100Hz の誤差は無視
max_delta = 0.1;         % 1ステップあたりの最大電圧変化量（スルーレート制限）

% ログ用変数
log_time = [];
log_error = [];
log_voltage = [];

disp('I制御（visadev版）を開始します...');
tic;
last_voltage = 0;

% 制御ループ（例：300秒 = 5分間動かす）
while toc < 300
    try
        % 周波数取得（CH1）
        writeline(osci, ":MEASure:FREQuency? CH1");
        f1 = str2double(readline(osci));
        
        % 周波数取得（CH2）
        writeline(osci, ":MEASure:FREQuency? CH2");
        f2 = str2double(readline(osci));
    catch
        warning("オシロスコープとの通信エラーが発生しました");
        continue;
    end
    
    % 周波数誤差
    error = f1 - f2;
    
    % デッドバンド処理
    if abs(error) > deadband
        integral = integral + error * dt;
        integral = min(max(integral, -integral_max), integral_max);
    end
    
    % 制御電圧計算
    control_voltage = Ki * integral;
    control_voltage = min(max(control_voltage, V_min), V_max);
    
    % スルーレート制限
    delta_v = control_voltage - last_voltage;
    if abs(delta_v) > max_delta
        control_voltage = last_voltage + sign(delta_v) * max_delta;
    end
    last_voltage = control_voltage;
    
    % 電圧出力
    outputSingleScan(daqSession, control_voltage);
    
    % ログ保存
    log_time(end+1) = toc;
    log_error(end+1) = error;
    log_voltage(end+1) = control_voltage;

    % 状況表示
    fprintf('t=%.1fs | f1=%.1fHz | f2=%.1fHz | err=%.1fHz | V=%.3fV\n', ...
        toc, f1, f2, error, control_voltage);

    pause(dt);
end

% 安全措置：制御電圧を0に
outputSingleScan(daqSession, 0);
disp('制御終了しました');

% --- 結果プロット ---
figure;
subplot(2,1,1);
plot(log_time, log_error);
ylabel('誤差 [Hz]');
title('I制御：周波数誤差ログ');

subplot(2,1,2);
plot(log_time, log_voltage);
ylabel('制御電圧 [V]');
xlabel('時間 [s]');
