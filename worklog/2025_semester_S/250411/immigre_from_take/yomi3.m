fid=fopen("drig1001.bin");
a=fread(fid,'uint8');
fclose(fid)

%最初の11bytesはヘッダ
MS=a(13:2:50e6+11);
LS=a(12:2:50e6+10);
b1=MS+LS/256;
figure;plot(MS);hold on;plot(b1)
hozon1=b1;


fid=fopen("drig1002.bin");
a=fread(fid,'uint8');
fclose(fid)

%最初の11bytesはヘッダ
MS=a(13:2:50e6+11);
LS=a(12:2:50e6+10);
b1=MS+LS/256;
hozon2=b1;
figure;plot(hozon1-hozon2)
