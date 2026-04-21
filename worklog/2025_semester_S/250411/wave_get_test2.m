if exist("dev", "var")
    clear dev
end

dev = visadev("USB0::0xF4EC::0x100C::SDS2HBAQ7R0280::INSTR");
dev.Timeout = 10;

try
    % CH1を波形ソースに設定
    writeline(dev, ":WAV:SOUR CHAN1");
    pause(0.1);

    % 波形モードをNORMAL
    writeline(dev, ":WAV:MODE NORM");
    pause(0.1);

    % データ形式をASCIIに
    writeline(dev, ":WAV:FORM ASC");
    pause(0.1);

    % 実際に波形データを要求
    writeline(dev, ":WAV:DATA?");
    raw = readline(dev);

    if strlength(raw) > 0
        disp("波形データ取得成功（先頭100文字）:");
        disp(raw(1:min(end,100)));  % 文字数が少ないときも安全
    else
        disp("波形データ：空の応答が返ってきました（バッファ空の可能性）");
    end

catch ME
    disp("波形取得に失敗:");
    disp(ME.message);
end

clear dev;
