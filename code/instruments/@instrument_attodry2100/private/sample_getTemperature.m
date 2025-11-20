function [errorNumber, sample_temperature] = sample_getTemperature(tcp)
% brief : Gets the sample temperature
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0
%           sample_temperature: 


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.getTemperature", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

errorNumber = data.result(1);
sample_temperature = data.result(2);


end