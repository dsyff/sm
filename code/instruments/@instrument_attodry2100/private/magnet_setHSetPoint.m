function [errorNumber] = magnet_setHSetPoint(tcp, channel, setPoint)
% brief : Sets the magnetic field set point
%
% param[in] tcp: TCP/IP connection ID
%           channel: 
%           setPoint: 
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.magnet.setHSetPoint", "params": [%i, %d], "id": 1, "api": 2}', channel, setPoint);

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

% Thomas edit (sm-dev): vendor wrapper made robust via attodry_parseResult
errorNumber = attodry_parseResult(data, 1, "magnet_setHSetPoint");


end