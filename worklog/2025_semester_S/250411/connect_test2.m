% 既存デバイス変数があればクリア
if exist("dev", "var")
    clear dev
end

% VISAデバイスを開く（リソース名は適宜変更）
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 20;  % 長めに設定

% CH1 波形設定（バイナリ形式）
writeline(dev, ":WAV:SOUR CHAN1");
writeline(dev, ":WAV:MODE NORM");
writeline(dev, ":WAV:FORM BYTE");
writeline(dev, ":WAV:POIN 1000");  % ← ポイント数を制限して安全に！

% データ取得コマンド送信
writeline(dev, ":WAV:DATA?");

% ヘッダ部分を最初に読む（例: "#41000" → data_len = 1000）
header_raw = read(dev, 10, "uint8");
num_digits = str2double(char(header_raw(2)));
len_str = char(header_raw(3:2 + num_digits));
data_len = str2double(len_str);

% 実データ部分を読み取り（バイナリ）
wave_bytes = read(dev, data_len, "uint8");

% 変換：0–255 → -1〜+1 （128中心）
voltages = (double(wave_bytes) - 128) / 128;

% プロット表示
figure;
plot(voltages);
title("CH1 波形（SIGLENT）");
xlabel("Point");
ylabel("Voltage (V)");
grid on;

% デバイスを閉じる
clear dev;
