function [errorNumber] = sample_startTempControl(tcp)
% brief : Starts the sample heater
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.startTempControl", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
errorNumber = attodry_parseResult(data_receive, 1, "sample_startTempControl");


end