%オシロとPCの接続確認
dev = visadev("TCPIP0::192.168.1.61::inst0::INSTR");
writeline(dev, "*IDN?");
resp = readline(dev);
disp("応答:");
disp(resp);
clear dev;
