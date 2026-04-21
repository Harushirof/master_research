% NIから指定電圧を10秒間出力し、0Vに戻す
function apply_voltage_10sec()

    % ----------- 設定エリア -------------
    target_voltage = 2.943 ; % 出力する電圧（単位：V）
    hold_time = 60;       % 出力時間（単位：秒）

    % NIデバイス情報（必要なら変更）
    device_name = 'Dev1'; % NIデバイス名
    channel_name = 'ao0'; % アナログ出力チャネル
    % -------------------------------------

    % NIセッション作成
    s = daq.createSession('ni');
    addAnalogOutputChannel(s, device_name, channel_name, 'Voltage');

    % 指定電圧出力
    outputSingleScan(s, target_voltage);
    fprintf('%.2f V を出力中。%d秒間保持します...\n', target_voltage, hold_time);

    % 出力保持
    pause(hold_time);

    % 0Vに戻す
    outputSingleScan(s, 0);
    fprintf('出力停止。電圧を0Vに戻しました。\n');

    % セッション終了
    release(s);

end

