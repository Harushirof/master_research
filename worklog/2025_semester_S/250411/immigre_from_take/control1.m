v=visadev("USB0::0x1AB1::0x0610::HDO1A250200011::0::INSTR");
pause('on')
format compact

v.Timeout=100;
writeread(v,"*IDN?");
flush(v,"input")
flush(v,"output")


write(v,"SINGle")
while 1
pause(1);
flag=writeread(v,"TRIG:STAT?");
fprintf('*')
if strfind(flag,"STOP")==1
    fprintf('\n')
    break
end
end %while

write(v,"WAV:SOUR CHAN1")
write(v,"WAV:MODE RAW")
write(v,"WAV:FORM WORD")
write(v,"WAV:STAR 1")
write(v,"WAV:STOP 25000000")
write(v,"WAV:DATA?")
clear d2
fprintf("transferring data\n")
d2=read(v,25000000,"uint16");
figure;plot(d2);shg



clear v
