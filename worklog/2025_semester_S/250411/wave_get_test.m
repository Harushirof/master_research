if exist("dev", "var")
    clear dev
end

dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

try
    % CH1を波形ソースに設定
    writeline(dev, ":WAV:SOUR CHAN1");
    pause(0.1);

    % 波形モードをNORMに
    writeline(dev, ":WAV:MODE NORM");
    pause(0.1);

    % データ形式をASCIIに
    writeline(dev, ":WAV:FORM ASC");
    pause(0.1);

    % 実際にデータ取得要求
    writeline(dev, ":WAV:DATA?");
    raw = readline(dev);
    disp("波形データ取得:");
    disp(raw(1:100));  % 最初の100文字だけ表示

catch ME
    disp("波形取得に失敗:");
    disp(ME.message);
end

clear dev;
