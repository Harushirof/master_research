% USBメモリに保存するので、差し込んでおくこと. 
%folder_name='c:\test\';
folder_name='d:\rigol\';
if not(exist(folder_name,'dir'))
    mkdir folder_name
end

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

fprintf("transferring data.  Do Not interrupt! \n")
write(v,"WAV:SOUR C2")
write(v,"WAV:WIDT WORD")
write(v,"WAV:STAR 1")
write(v,"FORM:DATA CUSTOM,8")
write(v,"WAV:POIN 6000000")
write(v,"WAV:DATA?")
%d2=read(v,5000004,"uint16");  通る
%d2=read(v,5000005,"uint16");通る
%d2=read(v,5000024,"uint16");通らない
%d2=read(v,5000008,"uint16");通らない
%d2=read(v,5000006,"uint16");通る
d2=read(v,5000007,"uint16");%6と7が境
%figure;plot(d2);shg

%fname=strcat(folder_name,'SIGLENT_C2',num2str(L),'.bin');
fname=strcat('SIGLENT_C2',num2str(L),'.bin');
fprintf('saving to %s\n',fname);
fid=fopen(fname,"w");
fwrite(fid,d2,"uint16");
fclose(fid);

end %for L

clear v
