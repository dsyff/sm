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

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
[errorNumber, sample_temperature] = attodry_parseResult(data_receive, 2, "sample_getTemperature");


end