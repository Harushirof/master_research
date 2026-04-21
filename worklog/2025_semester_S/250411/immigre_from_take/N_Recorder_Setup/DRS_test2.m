function DRS_test2()
    % DRS_test2.m
    % lecroy_basic_driver.mddを使用. 
    % 8bitに制限される. 波形取得が40秒以上かかる. 遅い.
    % tmtoolを使用すると経過を確認できる

    %% PINGで 192.168.1.52 の接続確認を行う
    % LECROY,WS4024HD,LCRY4903C19374,9.7.1
    !ping 192.168.1.51
    % LECROY,WS4024HD,LCRY4903C19377,9.7.1
    !ping 192.168.1.52
    % Agilent Technologies,33509B,MY52101249,3.03-1.19-2.00-52-00
    !ping 192.168.1.49

    %% tmtoolを起動
    tmtool;

    %% visadev Objectの生成
    % triggerIP="192.168.1.49";
    % triggerObj=visadev(strcat("TCPIP0::",triggerIP,"::inst0::INSTR"));
    % triggerObj.Timeout=10;
    
    %% recorderのIPアドレスを作成.
    N_recorder=2;
    recorderIP=string.empty(0,N_recorder);
    for i=1:N_recorder
        recorderIP(i)=sprintf("192.168.1.%d",50+i);
    end
    
    %% interface Objectの生成
    N_sample=25E+6; % 25MSa点のデータ.
    interfaceObj=instrument.empty(0,N_recorder);
    deviceObj=instrument.empty(0,N_recorder);
    for i=1:N_recorder
        interfaceObj(i) = tcpip(recorderIP(i), 1861);
        interfaceObj(i).InputBufferSize =2*N_sample+(1E+3);
        deviceObj(i) = icdevice('lecroy_basic_driver.mdd', interfaceObj(i));
        deviceObj(i).Name=sprintf("Recorder %d",i);
        connect(deviceObj(i));
    end

    %% 全てのrecorderをトリガーsingle状態にする.
    for i=1:N_recorder
        %    invoke(deviceObj(i), 'beep');
        %    pause(2);
        deviceObj(i).Trigger.Mode="single";
        deviceObj(i).Waveform.MaxNumberPoint=N_sample;
    end
    disp("waiting for data ready.");
    fprintf("waiting for trigger *")
    while deviceObj(1).Trigger.Mode~="stop"
        pause(1);
        fprintf("*");
    end
    fprintf("\n");

    %% readwaveform関数でrecorder 1のch2波形を取得する.
    tic;
    disp("readwaveform *****(wait about 40--80 seconds)*****");
    i=1;
    [Y,X,YUNIT,XUNIT,HEADER] = invoke(deviceObj(1).Waveform, 'readwaveform','channel2');
    fprintf("readwaveform required %f seconds\n",toc);
    plot(X,Y); % plot figure
    title('WaveMaster Waveform Data'); % label title
    xlabel('s'); % label x axis
    ylabel('V'); % label y axis

    %% Disconnect device object from hardware.
    disconnect(deviceObj);
    delete(deviceObj);
    clear("deviceObj");
    delete(interfaceObj);
    clear("interfaceObj");
    clear("triggerObj");
end