% 接続
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 100;

% ステータス確認
writeline(dev, ":ACQ:STAT?");
status = readline(dev);

% 結果表示
disp("オシロのステータス:");
disp(status);

clear dev;
