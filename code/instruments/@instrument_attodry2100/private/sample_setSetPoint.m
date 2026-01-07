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
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
errorNumber = attodry_parseResult(data, 1, "sample_setSetPoint");


end