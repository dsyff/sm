function [errorNumber] = sample_startTempControl(tcp)
% brief : Starts the sample heater
%
% param[in] tcp: TCP/IP connection ID
% param[out]
%           errorNumber: No error = 0


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.sample.startTempControl", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

errorNumber = data.result(1);


end