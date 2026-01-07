function [errorNumber] = sample_stopTempControl(tcp)
% brief : Stops the sample heater
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.stopTempControl", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
errorNumber = attodry_parseResult(data, 1, "sample_stopTempControl");


end