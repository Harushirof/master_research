dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

% パターン1（標準）
try
    writeline(dev, ":MEASure:ITEM? FREQ,CHAN1");
    disp("パターン1:");
    disp(readline(dev));
catch
    disp("パターン1失敗");
end

% パターン2（簡易）
try
    writeline(dev, ":MEAS:FREQ? CHAN1");
    disp("パターン2:");
    disp(readline(dev));
catch
    disp("パターン2失敗");
end

% パターン3（ソース設定後）
try
    writeline(dev, ":MEAS:SOUR CHAN1");
    writeline(dev, ":MEAS:FREQ?");
    disp("パターン3:");
    disp(readline(dev));
catch
    disp("パターン3失敗");
end

clear dev;
