function [errorNumber, field] = magnet_getH(tcp, channel)
% brief : Gets the magnetic field
%
% param[in] tcp: TCP/IP connection ID
%           channel: 
% param[out]
%           errorNumber: No error = 0
%           field: 


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.magnet.getH", "params": [%i], "id": 1, "api": 2}', channel);

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
[errorNumber, field] = attodry_parseResult(data, 2, "magnet_getH");


end