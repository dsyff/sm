function [errorNumber, channels] = magnet_getNumberOfMagnetChannels(tcp)
% brief : Gets the number of magnets
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0
%           channels: 


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.magnet.getNumberOfMagnetChannels", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
[errorNumber, channels] = attodry_parseResult(data, 2, "magnet_getNumberOfMagnetChannels");


end