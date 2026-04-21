function main_v3()
    % main_v2.m
    % NI-VISAを使用.
    % WaveSurfer 4024HDは, Utilities-> Utilities Setup -> Remote-> LXI(VXL11)に設定
    % Agilent,33509Bは, SubnetMast255.255.0.0, Gateway192.168.1.1に設定

    %% PINGで 192.168.1.52 の接続確認を行う
    % Agilent Technologies,33509B,MY52101249,3.03-1.19-2.00-52-00
    !ping 192.168.1.49
    % LECROY,WS4024HD,LCRY4903C19374,9.7.1
    !ping 192.168.1.51
    % LECROY,WS4024HD,LCRY4903C19377,9.7.1
    !ping 192.168.1.52
    % Siglent Technologies,SDS2204X HD,SDS2HBAQ7R0280,2.5.1.2.2.5
    !ping 192.168.1.61
    % Siglent Technologies,SDS2204X HD,SDS2HBAD7R0419,2.5.1.2.2.5
    !ping 192.168.1.62
    
    %% VISAオブジェクトを生成する.
    % Keysight 33509B のIPアドレス.
    triggerIP="192.168.1.49";
    triggerObj=visadev(strcat("TCPIP0::",triggerIP,"::inst0::INSTR"));
    % WaveSurfer 4024HD のIPアドレス.
    IP_WS4024HD=["192.168.1.51","192.168.1.52"];
    IP_SDS2204XHD=["192.168.1.61","192.168.1.62"];
    N_WS4024HD=length(IP_WS4024HD);
    N_SDS2204XHD=length(IP_SDS2204XHD);
    for i=1:N_WS4024HD
        wsObj(i)=visadev(strcat("TCPIP0::",IP_WS4024HD(i),"::inst0::INSTR"));
    end
    for i=1:N_SDS2204XHD
        sdsObj(i)=visadev(strcat("TCPIP0::",IP_SDS2204XHD(i),"::inst0::INSTR"));
    end

    %% 波形発生器を設定する. ADQ7DC の Trigger Input は 0V to 3.3V
    triggerObj.Timeout=10;  % 10秒でタイムアウト
    write(triggerObj,'APPLy:SQUare 0.5,2.5,1.25'); %方形波出力,0.5Hz,2.5Vpp,Offset 1.25V,ON.
    write(triggerObj,'BURSt:STATe ON');
    write(triggerObj,'BURSt:MODE TRIGgered');
    write(triggerObj,'BURSt:NCYCles 1');% burst cycleは1回とする.
    write(triggerObj,'BURSt:INTernal:PERiod 100');% burst periodを 100sにする.

    %% WaveSurferを設定する. SDS2204Xを設定する.
    for i=1:N_WS4024HD
        wsObj(i).Timeout=30; % 30秒でタイムアウト
        write(wsObj(i),"STST ALL_DISPLAYED,HDD,FORMAT,BINARY");
    end
%    ts=datetime('now','Format','HHmss');
%    fprintf("...Triggerd at %s\n",ts);
    for i=1:N_SDS2204XHD
        sdsObj(i).Timeout=30; % 30秒でタイムアウト
    end

    %% 動作確認のため, WaveSurferを1台ずつ, SINGLE -> Triggered -> STOP にする. 
    t_check=1; % トリガーモード確認は, 1秒ずつ繰り返す
    t_single=1; % singleボタンを押してから待機状態になるまで,1秒待つ.
    t_stop=2; % トリガーがかかってからSTOPか確認する前に,2秒待つ
    for i=1:N_WS4024HD
        fprintf("WS4024HD %d: ",i);
        ws_single_onebyone(triggerObj,wsObj(i),t_check,t_single,t_stop);
    end
    for i=1:N_SDS2204XHD
        fprintf("SDS2204XHD %d: ",i);
        ws_single_onebyone(triggerObj,sdsObj(i),t_check,t_single,t_stop);
    end

    %% 何度か試す.
    N_test=3;
    recObj=[wsObj,sdsObj];
    for i=1:N_test
        fprintf("recorder All: ");
        ws_single_all(triggerObj,recObj,t_check,t_single,t_stop);
        for buz=1:N_WS4024HD
            write(wsObj(buz),'BUZZ');
            pause(0.5);
        end
        pause(1);
    end

    %% 保存する
    N_run=5; % 測定回数.
    % t_save=6; % SDS2204XHDがUSBメモリに20MPt保存するのにかかる時間
    t_save=12; % SDS2204XHDがUSBメモリに40MPt保存するのにかかる時間
    for run=1:N_run
        fprintf("run no. %d start...",run);
        tic;
        ws_single_all(triggerObj,recObj,t_check,t_single,t_stop);
        for i=1:N_WS4024HD
            write(wsObj(i),"STO");
            fprintf("Saved in WaveSurfer no. %d\n",i);
        end
        write(sdsObj(1),strcat("SAVE:BIN ""U-disk0/C2_",num2str(999+run),".bin"",C2"))
        write(sdsObj(2),strcat("SAVE:BIN ""U-disk0/C2_",num2str(999+run),".bin"",C2"))
        pause(t_save);
        write(sdsObj(1),strcat("SAVE:BIN ""U-disk0/C3_",num2str(999+run),".bin"",C3"))
        write(sdsObj(2),strcat("SAVE:BIN ""U-disk0/C3_",num2str(999+run),".bin"",C3"))
        pause(t_save);
        fprintf("Saved in SDS2204XHD no. 1 and no. 2\n");        
        fprintf("run no. %d finished (%f seconds).\n",run,toc);
    end

    %% Disconnect device object from hardware.
    clear("wsObj");
    clear("sdsObj");
    clear("recObj");
    clear("triggerObj");

    %% きれいにする.
    % clearvars;
    % clc;
end

function ts=ws_single_all(tobj,robj,t1,t2,t3)
    fprintf("set trigger single...");
    num=size(robj,2);
    for i=1:num
        write(robj(i),'TRIG_MODE SINGLE');
    end
    while ~check_trig_mode(robj,"SING")
        fprintf(".");
        pause(t1);
    end
    pause(t2)
    fprintf("Ready for trigger...");
    while ~check_trig_mode(robj,"STOP")
        write(tobj,'TRIG');
        fprintf("*");
        pause(t3);
    end
    ts=datetime('now','Format','yyyyMMdd-HHmmss');
    fprintf("...Triggerd at %s\n",ts);
end

function ws_single_onebyone(tobj,robj,t1,t2,t3)
    fprintf("set trigger single...");
    write(robj,'TRIG_MODE SINGLE');
    while ~check_trig_mode(robj,"SING")
        fprintf(".");
        pause(t1); % トリガーモード確認は, t1 秒ずつ繰り返す
    end
    pause(t2); % singleボタンを押してから待機状態になるまで, t2 秒待つ.
    fprintf("Ready for trigger...");
    while ~check_trig_mode(robj,"STOP")
        write(tobj,'TRIG'); % ソフトウェアトリガーを出力.
        fprintf("*");
        pause(t3); % トリガーがかかってからSTOPか確認する前に, t3秒待つ
    end
    ts=datetime('now','Format','yyyyMMdd-HHmmss');
    fprintf("...Triggerd at %s\n",ts);
    write(robj,'BUZZ');% 2回ビープ音を鳴らす.
    pause(0.5);
    write(robj,'BUZZ');
    pause(0.5);
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

