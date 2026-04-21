%永遠にいれるver

% NIから指定電圧を出力し続ける（Ctrl+Cで停止）
function continuous_voltage_output()

    % ----------- 設定エリア -------------
    target_voltage = 1.0; % 出力する電圧（単位：V）

    % NIデバイス情報（必要なら変更）
    device_name = 'Dev1'; % NIデバイス名
    channel_name = 'ao0'; % アナログ出力チャネル
    % -------------------------------------

    % NIセッション作成
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, device_name, channel_name, 'Voltage');

    % 指定電圧出力開始
    fprintf('%.2f V を出力中（Ctrl+Cで停止）...\n', target_voltage);

    try
        while true
            outputSingleScan(s, target_voltage);
            pause(0.1); % 出力間隔、必要なら微調整
        end
    catch
        fprintf('\n停止検出。電圧を0Vに戻します。\n');
        outputSingleScan(s, 0);
        release(s);
        fprintf('出力停止、終了しました。\n');
    end

end
