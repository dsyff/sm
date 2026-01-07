function [errorNumber] = magnet_setDrivenMode(tcp, channel, onOrOff)
% brief : Set driven mode for a specific channel
%
% param[in] tcp: TCP/IP connection ID
%           channel:
%           onOrOff: drivenMode on or off
% param[out]
%           errorNumber: No error = 0

data_send = compose("{""jsonrpc"": ""2.0"", ""method"": ""com.attocube.cryostat.interface.magnet.setDrivenMode"", ""params"": [%d, %d], ""id"": 1, ""api"": 2}", channel, onOrOff);

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
errorNumber = attodry_parseResult(data, 1, "magnet_setDrivenMode");

end


