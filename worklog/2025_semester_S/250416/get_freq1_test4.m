%対象

dev = visadev("TCPIP0::192.168.1.61::inst0::INSTR");
writeline(dev, "MEAS:ADV:P1:VAL?");
disp(readline(dev));
clear dev;
