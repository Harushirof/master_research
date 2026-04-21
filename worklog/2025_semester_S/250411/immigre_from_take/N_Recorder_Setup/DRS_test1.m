%% PINGで 192.168.1.52 の接続確認を行う
% tmtoolを使用すると便利.
!ping 192.168.1.51 % 'LECROY,WS4024HD,LCRY4903C19374,9.7.1'
!ping 192.168.1.52 % 'LECROY,WS4024HD,LCRY4903C19377,9.7.1'
!ping 192.168.1.49 % トリガー用任意波形発生器

%% interface Objectの生成
IPaddress=["192.168.1.51","192.168.1.52","192.168.1.49"];
for i=1:2
    interfaceObj(i) = tcpip(IPaddress(i), 1861);
end
interfaceObj(:).InputBufferSize=2000000;
v=visadev("TCPIP0::192.168.1.49::inst0::INSTR");

%% device Objectの生成
% Create a device object. 
deviceObj(1) = icdevice('lecroy_basic_driver.mdd', interfaceObj(1));
deviceObj(1).Name="Recorder A";
deviceObj(2) = icdevice('lecroy_basic_driver.mdd', interfaceObj(2));
deviceObj(2).Name="Recorder B";

%% ビープ音を鳴らす
% Connect device object to hardware.

connect(deviceObj(1));
invoke(deviceObj(1), 'beep');

connect(deviceObj(2));
invoke(deviceObj(2), 'beep');

% Execute device object function(s).

%% 
deviceObj.Trigger.Mode="single";
deviceObj.Waveform.Precision="int8";
groupObj = get(deviceObj, 'Waveform');
[Y,X,YUNIT,XUNIT,HEADER] = invoke(groupObj, 'readwaveform','channel3');

plot(X,Y); % plot figure
title('WaveMaster Waveform Data'); % label title
xlabel('s'); % label x axis
ylabel('V'); % label y axis

%% Disconnect device object from hardware.
disconnect(deviceObj);
delete([deviceObj interfaceObj]);
