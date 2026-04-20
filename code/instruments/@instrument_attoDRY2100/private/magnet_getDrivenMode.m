function [errorNumber, drivenMode_on_or_off] = magnet_getDrivenMode(tcp, channel)
% brief : Checks if Magnet is in driven Mode (equivalent to NOT getPersistentMode)
%
% param[in] tcp: TCP/IP connection ID
%           channel:
% param[out]
%           errorNumber: No error = 0
%           drivenMode_on_or_off:

data_send = compose("{""jsonrpc"": ""2.0"", ""method"": ""com.attocube.cryostat.interface.magnet.getDrivenMode"", ""params"": [%d], ""id"": 1, ""api"": 2}", channel);

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
[errorNumber, drivenMode_on_or_off] = attoDRY_parseResult(data_receive, 2, "magnet_getDrivenMode");

end


