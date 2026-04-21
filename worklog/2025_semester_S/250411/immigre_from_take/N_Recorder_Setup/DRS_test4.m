function DRS_test3()
    % DRS_test2.m
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
    recorderIP=["192.168.1.51","192.168.1.52"];
    N_recorder=length(recorderIP);
    for i=1:N_recorder
        recorderObj(i)=visadev(strcat("TCPIP0::",recorderIP(i),"::inst0::INSTR"));
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
        single_onebyone(triggerObj,recorderObj(i),t_check,t_single,t_stop);
    end

    %% 動作確認のため, WaveSurferを全て同時に, SINGLE -> Triggered -> STOP にする. 
    fprintf("Recoder All: ");
    single_all(triggerObj,recorderObj,t_check,t_single,t_stop);
    for i=1:N_recorder
        write(recorderObj(i),'BUZZ');
    end

    %% WaveSurferを設定する.
    N_first=12; % 読み取った配列の12番目から測定値.
    channel=["C2","C3"]; % C2とC3を記録
    % N_points=12.5E+6; % 1波形あたりデータ点数は 12.5 MSa
    N_points=25E+6; % 1波形あたりデータ点数は 25 MSa
    N_channel=length(channel);
    for i=1:N_recorder
        recorderObj(i).Timeout=30; % 30秒でタイムアウト
        write(recorderObj(i),sprintf('WAVEFORM_SETUP SP,1,NP,%d,FP,0',N_points+N_first));
        write(recorderObj(i),'COMM_FORMAT DEF9, WORD, BIN');
        fprintf("Sent commands to recorder %d.\n",i);
    end

    %% 波形を保存する. 1波形ごとに10秒程度かかる.
    N_run=1; % 測定回数.
    varname=strings(1,N_channel*N_recorder);
    data=zeros(N_points+N_first,N_recorder*N_channel,"int16");
    for run=1:N_run
        ts=single_all(triggerObj,recorderObj,t_check,t_single,t_stop);    
        for i=1:N_recorder
            for j=1:N_channel
                k=2*(i-1)+j;
                varname(k)=sprintf("Rec%02dCh%d",i,j);
                flush(recorderObj(i),"input");
                flush(recorderObj(i),"output");
                fprintf("transferring data.  Do Not interrupt! ***(about %.0f s)*** ",14*N_points/25E+6);
                tic;
                write(recorderObj(i),sprintf("%s:WAVEFORM? DAT1",channel(j)));
                data(:,k)=int16(read(recorderObj(i),N_points+N_first,"int16"))';
                fprintf("%s recorder %d finished (%f seconds).\n",channel(j),i,toc);
                figure;
                plot(data(N_first:end,k));
                title(sprintf("RunNumber=%04d (%s), VarName=%s",run,ts,varname(k)));
                shg;
            end
        end
        filename=sprintf("NRS_%s_%04d.mat",ts,run);
        save(filename,"data","varname","N_first","ts",'-v7.3');
        fprintf("created file: %s\n",filename);
    end

    %% N_firstを確認するためにテーブルにする.
    data_table=array2table(data);

    %% Disconnect device object from hardware.
    clear("recorderObj");
    clear("triggerObj");

    %% きれいにする.
    clearvars;
    clc;
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

