function D = benchmark_extra_data()
%====================================================================
% 追加ベンチマーク位相雑音データ（260611 Web調査・出典検証済み43機種）
%
%   各機種: name, type, carrier_MHz, off[Hz], L[dBc/Hz](その搬送波での値), conf
%   ※ L はデータシート記載の搬送波(carrier_MHz)での値。10MHz換算は描画側で
%      L_10MHz = L + 20*log10(10/carrier_MHz) を適用する。
%   出典URLと注記は データ一覧_カタログ_260611.md「3.5 追加データ」を参照。
%
%   使い方: D = benchmark_extra_data();  → overlay_benchmark_full_10MHz が利用
%====================================================================
    D = struct('name',{},'type',{},'carrier_MHz',{},'off',{},'L',{},'conf',{});

    % ---- OCXO ----
    D = add(D,'Abracon AOCJY','OCXO',10,[1 10 100 1e3 1e4 1e5],[-90 -120 -135 -145 -150 -150],'high');
    D = add(D,'Micro Crystal Std OCXO','OCXO',10,[10 100 1e3 1e4 1e5],[-100 -130 -140 -145 -145],'med');
    D = add(D,'Morion MV89A','OCXO',5,[1 10 100 1e3 1e4],[-105 -130 -145 -150 -155],'high');
    D = add(D,'Connor-Winfield OH320-LA','OCXO',10,[1 10 100 1e3 1e4 1e5],[-85 -115 -140 -145 -150 -150],'low');
    D = add(D,'IQD IQOV-116','OCXO',10,[1e3],[-150],'med');
    D = add(D,'Oscilloquartz 8607 Std','OCXO',10,[1 10 100 1e3 1e4],[-118 -137 -143 -145 -145],'high');
    D = add(D,'Oscilloquartz 8607 OptL','OCXO',10,[1 10 100 1e3 1e4],[-122 -137 -143 -145 -145],'high');
    D = add(D,'Oscilloquartz 8788/8789 ULN','OCXO',10,[1 10 100 1e3 1e4 1e5],[-100 -130 -150 -157 -162 -162],'med');
    D = add(D,'Wenzel BTULN','OCXO',10,[1 1e4],[-120 -178],'med');
    D = add(D,'Cybershaft OP21A','OCXO',10,[1 10],[-121 -143],'high');
    D = add(D,'Cybershaft OP13','OCXO',10,[1 10],[-113 -137],'med');

    % ---- ルビジウム ----
    D = add(D,'SRS FS725 (Rb)','Rb',10,[10 100 1e3 1e4],[-130 -140 -150 -155],'high');
    D = add(D,'SRS PRS10 (Rb)','Rb',10,[10 100],[-130 -140],'high');
    D = add(D,'Microchip 8040C Std (Rb)','Rb',10,[1 10 100 1e3 1e4],[-72 -95 -130 -140 -148],'high');
    D = add(D,'Microchip 8040C LN (Rb)','Rb',10,[1 10 100 1e3 1e4],[-100 -130 -144 -150 -150],'high');
    D = add(D,'FEI FE-5680A (Rb)','Rb',10,[10 100 1e3],[-100 -125 -145],'high');
    D = add(D,'Datum LPRO-101 (Rb)','Rb',10,[1 10 100 1e3 1e4 1e5],[-86 -96 -138 -152 -156 -158],'med');
    D = add(D,'Spectratime mRO-50 (Rb)','Rb',10,[1 4 10 100 1e3 1e4],[-60 -70 -85 -110 -135 -140],'high');

    % ---- セシウム / 水素メーザー ----
    D = add(D,'Microchip 5071A Cs @5MHz','Cs',5,[1 10 100 1e3 1e4 1e5],[-106 -136 -145 -150 -154 -154],'high');
    D = add(D,'Microchip 5071A Cs @10MHz','Cs',10,[1 10 100 1e3 1e4 1e5],[-100 -130 -145 -150 -154 -154],'high');
    D = add(D,'T4Science iMaser3000 Std @5MHz','H-maser',5,[1 10 100 1e3 1e4 1e5],[-118 -135 -145 -152 -155 -155],'high');
    D = add(D,'T4Science iMaser3000 LN @5MHz','H-maser',5,[1 10 100 1e3 1e4 1e5],[-130 -142 -152 -156 -156 -156],'high');
    D = add(D,'T4Science iMaser3000 Std @100MHz','H-maser',100,[1 10 100 1e3 1e4 1e5],[-92 -105 -115 -125 -145 -145],'high');
    D = add(D,'Vremya-CH VCH-1003M Std @5MHz','H-maser',5,[1 10 100 1e3 1e4 1e5],[-118 -135 -149 -156 -158 -158],'high');
    D = add(D,'Vremya-CH VCH-1003M OptL @5MHz','H-maser',5,[1 10 100 1e3 1e4 1e5],[-130 -141 -151 -156 -159 -159],'high');
    D = add(D,'Vremya-CH VCH-1003M Std @100MHz','H-maser',100,[1 10 100 1e3 1e4 1e5],[-92 -109 -122 -122 -152 -152],'high');
    D = add(D,'Microchip SA.45s CSAC','Cs',10,[1 10 100 1e3 1e4 1e5],[-50 -70 -113 -128 -135 -140],'high');

    % ---- GPSDO / 規律発振器 ----
    D = add(D,'Leo Bodnar GPSDO','GPSDO',10,[1 10 100 1e3 1e4 1e5 1e6],[-70 -100 -125 -143 -150 -152 -155],'high');
    D = add(D,'Leo Bodnar Mini LBE-1420','GPSDO',10,[1 10 100 1e3 1e4 1e5 1e6],[-70 -100 -125 -145 -150 -153 -155],'high');
    D = add(D,'Trimble ThunderBolt','GPSDO',10,[10 100 1e3 1e4 1e5],[-120 -135 -135 -145 -145],'high');
    D = add(D,'Jackson Labs HD CSAC GPSDO','GPSDO',10,[10 100 1e3 1e4 1e5],[-75 -115 -128 -134 -140],'high');
    D = add(D,'Jackson Labs LN CSAC','GPSDO',10,[1 10 100 1e3 1e4 1e5],[-100 -135 -145 -150 -155 -155],'med');
    D = add(D,'Brandywine GPSDO','GPSDO',10,[1 10 100 1e3 1e4 1e5],[-90 -120 -145 -151 -153 -155],'high');
    D = add(D,'PTS GPS10eR Std (Rb-GPSDO)','GPSDO',10,[1 10 100 1e3 1e4 1e5],[-105 -135 -154 -157 -158 -159],'high');
    D = add(D,'PTS GPS10R/RB (Rb-GPSDO)','GPSDO',10,[1 10 100 1e3 1e4 1e5 1e6],[-96 -122 -138 -148 -150 -150 -154],'high');

    % ---- 低コスト MEMS / TCXO（対比用）----
    D = add(D,'SiTime SiT5356 (MEMS)','MEMS',10,[1 10 100 1e3 1e4 1e5],[-80 -108 -127 -148 -154 -154],'high');
    D = add(D,'SiTime SiT5155 (MEMS)','MEMS',10,[1 10 100 1e3 1e4 1e5],[-80 -108 -127 -148 -154 -154],'high');
    D = add(D,'Epson TG2520SMN (TCXO)','TCXO',26,[1 10 100 1e3 1e4 1e5 1e6],[-66 -94 -120 -142 -157 -161 -163],'high');
    D = add(D,'Abracon AST3TQ (TCXO)','TCXO',10,[10 100 1e3 1e4 1e5],[-95 -120 -140 -145 -150],'high');
    D = add(D,'NDK NT2016SA (TCXO)','TCXO',26,[10 100 1e3 1e4 1e5],[-83 -108 -132 -146 -150],'high');
end

function D = add(D,name,type,carrier,off,L,conf)
    D(end+1) = struct('name',name,'type',type,'carrier_MHz',carrier,'off',off,'L',L,'conf',conf); %#ok<AGROW>
end
