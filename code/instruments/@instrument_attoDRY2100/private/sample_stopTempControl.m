function [errorNumber] = sample_stopTempControl(tcp)
% brief : Stops the sample heater
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.stopTempControl", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
errorNumber = attoDRY_parseResult(data_receive, 1, "sample_stopTempControl");


end