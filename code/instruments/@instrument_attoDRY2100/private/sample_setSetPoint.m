function [errorNumber] = sample_setSetPoint(tcp, setPoint)
% brief : Sets the sample set point
%
% param[in] tcp: TCP/IP connection ID
%           setPoint: 
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.setSetPoint", "params": [%d], "id": 1, "api": 2}', setPoint);

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
errorNumber = attoDRY_parseResult(data_receive, 1, "sample_setSetPoint");


end