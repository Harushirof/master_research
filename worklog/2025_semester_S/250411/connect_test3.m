dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
writeline(dev, "*IDN?");
disp(readline(dev));
clear dev;
