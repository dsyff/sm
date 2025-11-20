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

errorNumber = data.result(1);
field = data.result(2);


end