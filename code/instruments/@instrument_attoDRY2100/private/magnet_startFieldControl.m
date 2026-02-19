function [errorNumber] = magnet_startFieldControl(tcp, channel)
% brief : Starts the magnetic field control
%
% param[in] tcp: TCP/IP connection ID
%           channel: 
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.magnet.startFieldControl", "params": [%i], "id": 1, "api": 2}', channel);

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
errorNumber = attoDRY_parseResult(data_receive, 1, "magnet_startFieldControl");


end