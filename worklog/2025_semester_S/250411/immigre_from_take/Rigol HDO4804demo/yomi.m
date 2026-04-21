fid=fopen('c:\test\drig_C21001.bin')
a=fread(fid,'uint8');
fclose(fid)
MS=a(1:2:end);
LS=a(2:2:end);
wa1=MS+MS/256;

fid=fopen('c:\test\drig_C31001.bin')
a=fread(fid,'uint8');
fclose(fid)
MS=a(1:2:end);
LS=a(2:2:end);
wa2=MS+MS/256;

figure;plot(wa1);hold on;plot(wa2)

