% 本体USBメモリに保存する
% 差し込んでおくこと. 

clear v
v=visadev("USB0::0xF4EC::0x100C::SDS2HBAQ6R0307::INSTR")

pause('on')
format compact

v.Timeout=100;
writeread(v,"*IDN?");

for L=1001:1010
flush(v,"input")
flush(v,"output")

write(v,"CLEar")%不明
write(v,"TRIG:MODE SING")
write(v,"TRIG:RUN")
fprintf('waiting for trigger *')
while 1
pause(1);
flag=writeread(v,"TRIG:STAT?");
fprintf('*')
if strfind(flag,"Stop")==1
    fprintf('\n')
    break
end
end %while
clear d2;

fprintf("saving data.  Do Not interrupt! \n")
write(v,strcat("SAVE:BIN ""U-disk0/C2_",num2str(L),".bin"",C2"))
pause(20);
write(v,strcat("SAVE:BIN ""U-disk0/C3_",num2str(L),".bin"",C3"))
pause(20);

end %for L

clear v
