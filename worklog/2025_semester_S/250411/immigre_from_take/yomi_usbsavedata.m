fid=fopen("rig1001bin");
%fseek(fid,1,"bof");
a=fread(fid,'uint8');
figure;plot(a)
fclose(fid)

b=a(2:2:100001);
b1=b+a(1:2:100000)/256;
figure;plot(b);hold on;plot(b1)
