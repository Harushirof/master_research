%2025/04/08

% === 接続 ===
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");

% === *IDN? で応答確認 ===
writeline(dev, "*IDN?");
idn = readline(dev);
% === 表示 ===
disp("オシロスコープの識別情報:");
disp(idn);

% === クリーンアップ ===
clear dev;
