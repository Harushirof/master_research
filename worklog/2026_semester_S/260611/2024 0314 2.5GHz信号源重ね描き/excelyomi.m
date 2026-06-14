figure;
figure;
kijun=0.02 %多分GHz

devname="Ceyear2G"
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')


devname=[devname,"Ceyear3G"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"DST2"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"DST1"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"SPXONo1"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"OEO"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"Abracon-U"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"EPSON-VCSO"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"TCXO-CMOS"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')

devname=[devname,"iMaser-10MLN"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')


devname=[devname,"PRS10"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')


devname=[devname,"DST-24.576"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')


devname=[devname,"cybershaft(638000円)"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')


devname=[devname,"cybershaft(121,000円)"]
datasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A3:A3")
N=cell2mat(datasuu)
syuhasuu = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range","A2:A2")
f=cell2mat(syuhasuu)
C = readcell("dBCperHz.xlsx","Sheet",devname(end),"Range",strcat("A4:B",num2str(3+N)))
a=cell2mat(C)
figure(1)
plot(a(:,1),a(:,2),'o-')
hold on
set(gca,'xscale','log')
figure(2)
plot(a(:,1),a(:,2)+20*log(kijun/f)/log(10),'o-')
hold on
set(gca,'xscale','log')
figure(1);legend(devname);title("そのままplot")
figure(2);legend(devname);title("20MHzに換算")
