%2025/04/11

% === デバイスに接続 ===
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");

% === CH1の周波数取得 ===
writeline(dev, ":MEASure:ITEM? FREQ,CHAN1");
freq1 = str2double(readline(dev));
fprintf("CH1の周波数：%.6f Hz\n", freq1);

% === CH2の周波数取得 ===
writeline(dev, ":MEASure:ITEM? FREQ,CHAN2");
freq2 = str2double(readline(dev));
fprintf("CH2の周波数：%.6f Hz\n", freq2);

% === クリーンアップ ===
clear dev;
