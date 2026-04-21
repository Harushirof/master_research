function hioki_v1()
    %% PINGで 192.168.1.71 の接続確認を行う
    % HIOKI 8420
    !ping 192.168.1.71
    %% 動作確認
    LoggerIP="192.168.1.71";
    LoggerObj=visadev(strcat("TCPIP0::",LoggerIP,"::inst0::INSTR"));


    %% バイナリファイルの読み取り
    N_analog_ch=5;
    N_puluse_ch=0;
    N_logic_ch=0;
    size_header=512*(18+N_analog_ch+N_puluse_ch+N_logic_ch);
    fileID=fopen("MEMALL.MEM");
    A=fread(fileID,8);
    B=A(size_header:end);
end