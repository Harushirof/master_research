function f=bwlimit3(x,Lflimit,Uflimit,fs)
%
% xのサイズ、fsとも偶数を仮定 10なら1 2345 6 789(10)
% 1がDC (Nx+1)がfsに正確に対応　なので、1+flimit/fs*Nxがflimitに対応 0なら1,fsならNx+1
%図は5/2のノートにあり
Nx=max(size(x));
fftmoto=fft(x);
fftmoto2=zeros(size(fftmoto))+i*zeros(size(fftmoto));
NLflimit=round(1+Lflimit/fs*Nx);
NUflimit=round(1+Uflimit/fs*Nx);
fftmoto2(NLflimit:NUflimit,:)=fftmoto(NLflimit:NUflimit,:); 
fftmoto2(1,:)=fftmoto2(1,:)/2;%あとで2倍するので、2つない部分はここで1/2
fftmoto2(Nx/2+1,:)=fftmoto2(Nx/2+1,:)/2;%あとで2倍するので、2つない部分はここで1/2
f=2*real(ifft(fftmoto2));


