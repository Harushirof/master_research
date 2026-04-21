% USBメモリに保存するので、差し込んでおくこと. 
%folder_name='c:\test\';

%!ping 192.168.1.90

%%
folder_name='d:\rigol\';
clear v
v=visadev("TCPIP0::192.168.1.90::inst0::INSTR");

pause('on')
format compact

v.Timeout=100;
writeread(v,"*IDN?");

%%
% SINGLEボタンを手動で押す場合autosave=0
autosave=0;
for L=1001:1004
    flush(v,"input")
    flush(v,"output")

    write(v,"CLEar")
    if autosave==1
        write(v,"SINGle");
        fprintf('waiting for trigger *')
    else
        fprintf('push single button *')
        while 1
            pause(1);
            flag=writeread(v,"TRIG:STAT?");
            fprintf('*')
            if strfind(flag,"WAIT")==1
                fprintf('\n')
                break
a            end
        end %while
        fprintf('waiting for trigger *')
    end    
    while 1
        pause(1);
        flag=writeread(v,"TRIG:STAT?");
        fprintf('*')
        if strfind(flag,"STOP")==1
            fprintf('\n')
            break
        end
    end %while

    for ch_num=2:2:4
        cmd=sprintf("WAV:SOUR CHAN%1d",ch_num);
        write(v,cmd)
        write(v,"WAV:MODE RAW")
        write(v,"WAV:FORM WORD")
        write(v,"WAV:STAR 1")
        write(v,"WAV:STOP 50000000")
        write(v,"WAV:DATA?")
        clear d2
        fprintf("transferring data.  Do Not interrupt! \n")
        d2=read(v,50000006,"uint16");
        % figure;plot(d2);shg

        fname=strcat(folder_name,sprintf("drig_C%1d",ch_num),num2str(L),'.bin');
        fprintf('saving to %s\n',fname);
        fid=fopen(fname,"w");
        fwrite(fid,d2,"uint16");
        fclose(fid);
    end %for ch_num
end %for L
%%

clear v
