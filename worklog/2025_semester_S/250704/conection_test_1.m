%接続確認成7/4現在

ip = '192.168.1.61';
visaObj = visa('NI', ['TCPIP0::' ip '::inst0::INSTR']);

try
    fopen(visaObj);
    disp('接続成功');
    
    % SCPIコマンド送信
    fprintf(visaObj, '*IDN?');
    
    % 応答受信
    idn = fscanf(visaObj);
    disp(['機器情報: ' idn]);

catch ME
    disp('接続エラー:');
    disp(ME.message);
end

if strcmp(visaObj.Status, 'open')
    fclose(visaObj);
end
delete(visaObj);
clear visaObj;

