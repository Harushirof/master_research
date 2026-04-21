dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;  % 応答待ち時間を長めに

writeline(dev, "*IDN?");
resp = readline(dev);
disp("識別応答:");
disp(resp);

% 念のためクリア
clear dev;
