if exist("dev", "var")
    clear dev
end

dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

% 波形設定（バイナリ形式）
writeline(dev, ":WAV:SOUR CHAN1");
writeline(dev, ":WAV:MODE NORM");
writeline(dev, ":WAV:FORM BYTE");

% データ取得コマンド送信
writeline(dev, ":WAV:DATA?");

% --- ヘッダ（先頭10バイト分）をまず読む ---
header_raw = read(dev, 10, "uint8");

if char(header_raw(1)) ~= '#'
    error("データヘッダが不正です。先頭が '#' ではありません。");
end

num_digits = str2double(char(header_raw(2)));
len_str = char(header_raw(3:2 + num_digits));
data_len = str2double(len_str);

% --- バイナリ本体を読み込む ---
wave_bytes = read(dev, data_len, "uint8");

% --- 電圧にスケーリング（0–255 → -1~1 想定）
voltages = (double(wave_bytes) - 128) / 128;

% プロット
plot(voltages);
title("CH1 波形");
xlabel("Point");
ylabel("Voltage (V)");

clear dev;
