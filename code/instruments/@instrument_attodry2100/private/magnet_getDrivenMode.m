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
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
[errorNumber, drivenMode_on_or_off] = attodry_parseResult(data, 2, "magnet_getDrivenMode");

end


