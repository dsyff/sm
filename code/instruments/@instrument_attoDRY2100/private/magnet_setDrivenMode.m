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

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
errorNumber = attoDRY_parseResult(data_receive, 1, "magnet_setDrivenMode");

end


