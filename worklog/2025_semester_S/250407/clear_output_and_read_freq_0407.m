% clear_output_and_read_freq_0407.m
% 出力をクリアし、ctr0での周波数測定のみを行う
% 作成日：2025-04-07

% --- ステップ1: 出力を解除 ---
try
    dq_out = daq("ni");
    addoutput(dq_out, "Dev1", "ao0", "Voltage");
    write(dq_out, 0.0, "OutputFormat", "Matrix");  % 出力電圧を0Vに戻す
    release(dq_out);  % リソースを明示的に開放
    disp("AO出力を0Vにリセットしました。");
catch
    warning("AO出力リセット中にエラーが発生しましたが、無視して続行します。");
end

% --- ステップ2: 周波数入力の設定と測定 ---
try
    dq_in = daq("ni");
    addinput(dq_in, "Dev1", "ctr0", "Frequency");
    freq = read(dq_in, "OutputFormat", "Matrix");
    fprintf("測定された周波数: %.2f Hz\n", freq);
catch ME
    disp("入力測定に失敗しました。詳細:");
    disp(ME.message);
end
