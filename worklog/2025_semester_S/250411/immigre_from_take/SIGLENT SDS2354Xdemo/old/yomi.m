fid=fopen("SIGLENT_C21001.bin");
fseek(fid,1,'bof');
a=fread(fid,'int16');
fclose(fid)
plot(a)
