function DRS_test3()
    % DRS_test2.m
    % NI-VISAを使用.
    % WaveSurfer 4024HDは, Utilities-> Utilities Setup -> Remote-> LXI(VXL11)に設定
    % Agilent,33509Bは, SubnetMast255.255.0.0, Gateway192.168.1.1に設定

    %% PINGで 192.168.1.52 の接続確認を行う
    % LECROY,WS4024HD,LCRY4903C19374,9.7.1
    !ping 192.168.1.51
    % LECROY,WS4024HD,LCRY4903C19377,9.7.1
    !ping 192.168.1.52
    % Agilent Technologies,33509B,MY52101249,3.03-1.19-2.00-52-00
    !ping 192.168.1.49
    
    %% VISAオブジェクトを作成.
    % WaveSurfer 4024HD のIPアドレス.
    recorderIP=["192.168.1.51","192.168.1.52"];
    N_recorder=length(recorderIP);
    % Keysight 33509B のIPアドレス.
    triggerIP="192.168.1.49";
    
    triggerObj=visadev(strcat("TCPIP0::",triggerIP,"::inst0::INSTR"));
    for i=1:N_recorder
        recorderObj(i)=visadev(strcat("TCPIP0::",recorderIP(i),"::inst0::INSTR"));
    end

    %% 波形発生器の出力をDC-2.5V, ONにする.
    triggerObj.Timeout=10;
    write(triggerObj,'FUNCtion DC');
    write(triggerObj,'OUTPut ON');
    write(triggerObj,'VOLTage:OFFSet -2.5 V');
    disp("335509B OUTPut: -2.5 V.");
    
    %% WaveSurferの波形保存前の設定変更
    timeout=20;
    N_points=25E+6;
    for i=1:N_recorder
        recorderObj(i).Timeout=timeout;
        write(recorderObj(i),sprintf('WAVEFORM_SETUP SP,1,NP,%d,FP,0',N_points));
        write(recorderObj(i),'COMM_FORMAT DEF9, WORD, BIN');
        fprintf("recorder %d initialized.\n",i);
    end

    %% 波形発生器の出力をDC-2.5Vに変更し, WaveSurferのトリガーをSINGLEにする.
    write(triggerObj,'VOLTage:OFFSet -2.5 V');
    disp("335509B OUTPut: -2.5 V.");
    for i=1:N_recorder
        write(recorderObj(i),'TRIG_MODE SINGLE');
    end
    fprintf("checking trigger status...");
    if check_trig_mode(recorderObj,"SINGLE")
        disp("Ready for trigger !");
    else
        disp("Error. All recorders are not SINGLE.");
    end        
    pause(1);

    %% 33509BにDC+2.5Vを出力させ, WaveSurferをSTOPさせる
    write(triggerObj,'VOLTage:OFFSet 2.5 V');
    disp("335509B OUTPut: +2.5 V");
    fprintf("checking trigger status...");
    if check_trig_mode(recorderObj,"STOP")
        disp("Triggered successfully !");
    else
        disp("Error. All recorders are not STOP.");
    end        

    %% 波形を保存する. 1波形ごとに10秒程度かかる. 
    dataC2=zeros(N_recorder,N_points,"int16");
    dataC3=zeros(N_recorder,N_points,"int16");
    channel=["C2","C3"];
    for j=1:1% 1:1 C2のみ
        for i=1:N_recorder
            flush(recorderObj(i),"input");
            flush(recorderObj(i),"output");
            fprintf("transferring data.  Do Not interrupt! *** ");
            tic;
            write(recorderObj(i),sprintf("%s:WAVEFORM? DAT1",channel(j)));
            if channel(j)=="C2"
                dataC2(i,:)=read(recorderObj(i),N_points,"int16");
            end
            if channel(j)=="C3"
                dataC3(i,:)=read(recorderObj(i),N_points,"int16");
            end
            fprintf("%s recorder %d finished (%f seconds).\n",channel(j),i,toc);
            flush(recorderObj(i),"input");
            flush(recorderObj(i),"output");
            figure;hold("on");plot(dataC2(i,:));plot(dataC3(i,:));hold("off");legend("C2","C3"),title(sprintf("recorder %d",i));shg;
        end
    end

    %    msg=writeread(recorderObj(i),"*IDN?");
    %    msg=writeread(recorderObj(i),"COMM_FORMAT?");
    %    msg=writeread(recorderObj(i),'C2:INSPECT? "TIMEBASE"');
    %    write(recorderObj(i),'*IDN?');
    %    clear("msg");
    %    msg=read(recorderObj(i),512,'char');
    %    dataC2=writeread(recorderObj(i),'C2:INSPECT? "DATA_ARRAY_1", WORD');

    %% Disconnect device object from hardware.
    clear("recorderObj");
    clear("triggerObj");

    %% きれいにする.
    clearvars;
    clc;
end

function res=check_trig_mode(robj,status)
    rec_ok=0;
    num=size(robj,2);
    for i=1:num
        flag=writeread(robj(i),'TRIG_MODE?');
        if contains(flag,status)>0
            rec_ok=rec_ok+1;
        end
    end
    if rec_ok==num
        res=true;
    else
        res=false;
    end
end