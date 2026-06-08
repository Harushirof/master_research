amoto=audioread("2605150019.wav");
fs=192000;
start=10000+50*fs;
hani=(start+1):(start+fs*10);
amoto2=amoto(hani,:);
isou=zeros(size(amoto2));

for ch=1:2
aw=amoto2(:,ch);

%ヒルベルト変換　% 1-10なら、1, 2345, 6, 789(10)
%awをヒルベルト変換
N=max(size(aw));
a2=fft(aw);a2((N/2+2):N)=-a2((N/2+2):N);a3=imag(ifft(a2));
angle1=angle(aw(:,1)+i*a3(:,1));
angle2=unwrap(angle1);
isou(:,ch)=angle2;

%傾きの求めかた 横軸X 縦軸Yとする ax+bのフィッテングでa,bを求めるには、
%　A =[ sum(X.^2)  sum(X);  A[a; b]=[sum(X.*Y); sum(Y)]
%      sum(X)     N    ]
%Y=angle2((Nzc/4+1):(Nzc/4+Nzc)); % なにかしら前後は切る必要ありそう
Y=angle2;
X=(1:max(size(Y)))';
N2=size(X)*[1 0]';
A=[sum(X.^2) sum(X);sum(X) N2];
keisuu=inv(A)*[sum(X.*Y);sum(Y)];
Y2=X.*keisuu(1)+keisuu(2);
%Yはアングル　Yが1増えるのに、1/keisuu(1)だけ要する。周期は2*pi/keisuu(1)なので、keusuu(1)が角振動数相当
% keisuu(1)*192000/(2*pi) =      1.200000000000810e+04
% このようにkeisuu(1)*192000が角振動数
omega0h=keisuu(1)*192000;
omega0h/(2*pi);
fh=omega0h/(2*pi);
fprintf('fc obtained by Hirbert transform = %d \n',fh)

%位相の初期値は
phi0h=keisuu(1)+keisuu(2);

%
jitter_hirbert=(Y-Y2)/(2*pi*48000);
fs=192000;
j(:,ch)=bwlimit3(jitter_hirbert,0,12000,fs);
end %for ch=1:2
sa=j(:,1)-j(:,2);

sa2=sa(5001:(end-5000));
figure;plot(abs(fft(sa2)).^2)
set(gca,'yscale','log');set(gca,'xscale','log')
figure;plot(sa2)
std(sa2)

