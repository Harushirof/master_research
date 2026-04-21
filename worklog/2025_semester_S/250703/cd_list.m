fprintf(visaObj, ':MEAS:LIST?');
disp(fscanf(visaObj));
