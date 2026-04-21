function main_v2()
    % main_v2.m
    % NI-VISAを使用.
    % WaveSurfer 4024HDは, Utilities-> Utilities Setup -> Remote-> LXI(VXL11)に設定
    % Agilent,33509Bは, SubnetMast255.255.0.0, Gateway192.168.1.1に設定

    %% PINGで 192.168.1.52 の接続確認を行う
    % % LECROY,WS4024HD,LCRY4903C19374,9.7.1
    % !ping 192.168.1.51
    % % LECROY,WS4024HD,LCRY4903C19377,9.7.1
    % !ping 192.168.1.52
    % % Agilent Technologies,33509B,MY52101249,3.03-1.19-2.00-52-00
    % !ping 192.168.1.49
    
    %% VISAオブジェクトを生成する.
    % Keysight 33509B のIPアドレス.
    triggerIP="192.168.1.49";
    triggerObj=visadev(strcat("TCPIP0::",triggerIP,"::inst0::INSTR"));
    % WaveSurfer 4024HD のIPアドレス.
    IP_WS4024HD=["192.168.1.51","192.168.1.52"];
    N_WS4024HD=length(IP_WS4024HD);
    N_recorder=N_WS4024HD;
    for i=1:N_WS4024HD
        wsObj(i)=visadev(strcat("TCPIP0::",IP_WS4024HD(i),"::inst0::INSTR"));
    end

    %% 波形発生器を設定する.
    triggerObj.Timeout=10;  % 10秒でタイムアウト
    write(triggerObj,'APPLy:SQUare 0.5,2.5'); %方形波出力,0.5Hz,2.5Vpp,ON.
    write(triggerObj,'BURSt:STATe ON');
    write(triggerObj,'BURSt:MODE TRIGgered');
    write(triggerObj,'BURSt:NCYCles 1');% burst cycleは1回とする.
    write(triggerObj,'BURSt:INTernal:PERiod 100');% burst periodを 100sにする.

    %% 動作確認のため, WaveSurferを1台ずつ, SINGLE -> Triggered -> STOP にする. 
    t_check=1; % トリガーモード確認は, 1秒ずつ繰り返す
    t_single=1; % singleボタンを押してから待機状態になるまで,1秒待つ.
    t_stop=2; % トリガーがかかってからSTOPか確認する前に,2秒待つ
    for i=1:N_recorder
        fprintf("recorder %d: ",i);
        single_onebyone(triggerObj,wsObj(i),t_check,t_single,t_stop);
    end

    %% WaveSurferを設定する.
    for i=1:N_WS4024HD
        wsObj(i).Timeout=30; % 30秒でタイムアウト
        write(wsObj(i),"STST ALL_DISPLAYED,HDD,FORMAT,BINARY");
    end
    
    %% 何度か試す.
    N_test=1;
    for i=1:N_test
        fprintf("recorder All: ");
        single_all(triggerObj,wsObj,t_check,t_single,t_stop);
        for buz=1:N_recorder
            write(wsObj(buz),'BUZZ');
            pause(0.5);
        end
    end

    %% 保存する
    N_run=103; % 測定回数.
    for run=1:N_run
        fprintf("run no. %d start...",run);
        tic;
        single_all(triggerObj,wsObj,t_check,t_single,t_stop);
        for i=1:N_WS4024HD
            write(wsObj(i),"STO");
            fprintf("Saved in WaveSurfer no. %d\n",i);
        end
        fprintf("run no. %d finished (%f seconds).\n",run,toc);
        pause(1);
    end

    %% Disconnect device object from hardware.
    clear("wsObj");
    clear("triggerObj");

    %% きれいにする.
    % clearvars;
    % clc;
end

function ts=single_all(tobj,robj,t1,t2,t3)
    fprintf("set trigger single...");
    num=size(robj,2);
    for i=1:num
        write(robj(i),'TRIG_MODE SINGLE');
    end
    while ~check_trig_mode(robj,"SINGLE")
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

function single_onebyone(tobj,robj,t1,t2,t3)
    fprintf("set trigger single...");
    write(robj,'TRIG_MODE SINGLE');
    while ~check_trig_mode(robj,"SINGLE")
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

