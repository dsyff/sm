global instrumentRackGlobal smscan smaux smdata bridge tareData;
close all;
% Clean up existing instruments to release serial ports
if exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal)
    try
        delete(instrumentRackGlobal);
    catch ME
        fprintf("sminit deleteInstrumentRackGlobalFailed: %s\n", ME.message);
    end
    clear instrumentRackGlobal;
end

delete(visadevfind);
delete(serialportfind);
clear;
%clear all;
global instrumentRackGlobal smscan smaux smdata bridge tareData;

