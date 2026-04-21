% 接続
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;  % 秒単位で設定（デフォルトはたぶん 5）

% 周波数取得（CH1）
writeline(dev, ":MEASure:ITEM? FREQ,CHAN1");
resp = readline(dev);
disp("CH1応答:");
disp(resp);
