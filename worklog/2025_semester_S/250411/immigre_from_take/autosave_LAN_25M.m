folder_name='D:\rigol\';
if not(exist(folder_name,'dir'))
    mkdir folder_name
end

clear v
%v=visadev("USB0::0x1AB1::0x0610::HDO1A250200011::0::INSTR");
v=visadev("TCPIP0::192.168.1.101::inst0::INSTR")

pause('on')
format compact

v.Timeout=100;
writeread(v,"*IDN?");

for L=1001:2000
flush(v,"input")
flush(v,"output")

write(v,"CLEar")

write(v,"SINGle")
fprintf('waiting for trigger *')
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
fprintf("transferring data.  Do Not interrupt! \n")
d2=read(v,25000006,"uint16");
%figure;plot(d2);shg

fname=strcat(folder_name,'drig',num2str(L),'.bin');
fprintf('saving to %s\n',fname);
fid=fopen(fname,"w");
fwrite(fid,d2,"uint16");
fclose(fid);

end %for L

clear v
