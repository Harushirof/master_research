function read_freq()
    %% 
    !ping 192.168.1.62

    %% VISAオブジェクトを生成する.
    % IP_SDS2204XHD=["192.168.1.61","192.168.1.62"];
    IP_SDS2204XHD=["192.168.1.62"];
    N_SDS2204XHD=length(IP_SDS2204XHD);
    for i=1:N_SDS2204XHD
        sdsObj(i)=visadev(strcat("TCPIP0::",IP_SDS2204XHD(i),"::inst0::INSTR"));
    end

    %% 現在時刻とタイムアウトを設定する
    ts_sds=datetime('now','Format','HHmmss');
    for i=1:N_SDS2204XHD
        sdsObj(i).Timeout=30; % 30秒でタイムアウト
        write(sdsObj(i),sprintf("SYSTEM:TIME %s",ts_sds));
    end

    %% 
    for i=1:N_SDS2204XHD
        ans=writeread(sdsObj(i),sprintf("*IDN?"));
    end
    %%
    for i=1:N_SDS2204XHD
        N_ch=3;
        write(sdsObj(i),sprintf("MEAS:ADV:P%0d ON",N_ch));
        write(sdsObj(i),sprintf("MEAS:ADV:P%0d:TYPE FREQ",N_ch));
        write(sdsObj(i),sprintf("MEAS:ADV:P%0d:VAL?",N_ch));
        freq=readline(sdsObj(i));
    end
    %% Disconnect device object from hardware.
    clear("sdsObj");

    %% きれいにする.
    clearvars;
    clc;


end