% USBメモリに保存するので、差し込んでおくこと. 
%folder_name='c:\test\';
folder_name='d:\rigol\';
if not(exist(folder_name,'dir'))
    mkdir folder_name
end

clear v

v=visadev("TCPIP0::192.168.1.201::inst0::INSTR")

pause('on')
format compact

v.Timeout=100;
writeread(v,"*IDN?");

for L=1001:1010
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

for chan=1:4
    write(v,sprintf("WAV:SOUR CHAN%d",chan))
    write(v,"WAV:MODE RAW")
    write(v,"WAV:FORM WORD")
    write(v,"WAV:STAR 1")
    write(v,"WAV:STOP 10000000")
    write(v,"WAV:DATA?")
    clear d2
    fprintf("transferring data.  Do Not interrupt! \n")
    d2=read(v,10000006,"uint16");
%figure;plot(d2);shg

    fname=strcat(folder_name,'drig_C',sprintf("%d",chan),num2str(L),'.bin');
    fprintf('saving to %s\n',fname);
    fid=fopen(fname,"w");
    fwrite(fid,d2,"uint16");
    fclose(fid);
end % for chan


end %for L

clear v
