if exist("dev", "var")
    clear dev
end

dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

% 波形取得設定
writeline(dev, ":WAV:SOUR CHAN1");
writeline(dev, ":WAV:MODE NORM");
writeline(dev, ":WAV:FORM ASC");

% データ取得
writeline(dev, ":WAV:DATA?");
raw = readline(dev);

% --- ヘッダ処理とパース ---
try
    if startsWith(raw, "#")
        num_digits = str2double(extractBetween(raw, 2, 2)); % "#4" → 4桁分の長さ情報
        data_len = str2double(extractBetween(raw, 3, 2 + num_digits)); % データ長

        % 実データの先頭位置（インデックス）
        data_start = 3 + num_digits;
        wave_str = raw(data_start:end);  % 波形データ文字列

        % カンマ区切りで分割して数値化
        wave_values = str2double(split(wave_str, ","));

        % プロット
        plot(wave_values);
        title("CH1 波形");
        xlabel("Point");
        ylabel("Voltage (V)");
    else
        disp("データ形式が #4xxxxx... ではありません。");
    end
catch ME
    disp("波形データのパースに失敗:");
    disp(ME.message);
end

clear dev;
