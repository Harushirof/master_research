%変にトリガーをいじっているので失敗

% オシロスコープのIPアドレス
ip = '192.168.1.61';

% VISAオブジェクト作成
visaObj = visa('NI', ['TCPIP0::' ip '::inst0::INSTR']);
visaObj.InputBufferSize = 1000000; % バッファ大きめに確保

try
    fopen(visaObj);
    disp('接続成功');

    % データ形式をASCIIに設定
    fprintf(visaObj, 'DATA:ENCdg ASCii');
    fprintf(visaObj, 'DATA:WIDTH 1'); % 1バイト幅

    % ループしてリアルタイム取得
    figure;
    while true
        % CH1波形取得
        fprintf(visaObj, 'WAVeform:SOURce CHANnel1');
        fprintf(visaObj, 'WAV:DATA?');
        rawData1 = fscanf(visaObj);

        % CH2波形取得
        fprintf(visaObj, 'WAVeform:SOURce CHANnel2');
        fprintf(visaObj, 'WAV:DATA?');
        rawData2 = fscanf(visaObj);

        % データ整形
        y1 = str2num(rawData1); %#ok<ST2NM>
        y2 = str2num(rawData2); %#ok<ST2NM>
        n = min(length(y1), length(y2));
        t = linspace(0, 1, n); % 仮の時間軸

        % 描画
        clf;
        plot(t, y1(1:n), 'b-', t, y2(1:n), 'r-');
        legend('CH1', 'CH2');
        xlabel('時間（仮）');
        ylabel('電圧 [V]');
        title('リアルタイム波形');
        drawnow;

        pause(0.1); % 更新間隔（調整可）
    end

catch ME
    disp('エラー発生:');
    disp(ME.message);
end

% リソース解放
if strcmp(visaObj.Status, 'open')
    fclose(visaObj);
end
delete(visaObj);
clear visaObj;
