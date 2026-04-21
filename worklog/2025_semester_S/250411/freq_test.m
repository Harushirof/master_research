dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

% CH1の周波数取得
writeline(dev, ":MEASure:ITEM? FREQ,CHAN1");
freq1 = str2double(readline(dev));
fprintf("CH1周波数: %.6f Hz\n", freq1);

clear dev;
