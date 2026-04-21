% CH1 表示状態を取得
dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
writeline(dev, ":CHAN1:DISP?");
resp = readline(dev);
disp("CH1 表示状態 (1=表示, 0=非表示):");
disp(resp);
clear dev;
