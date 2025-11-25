function [error] = system_errorNumberToString(tcp, errorNumber)
% brief : “Translate” the error code into an error text    Currently we only support the system language
%
% param[in] tcp: TCP/IP connection ID
%           errorNumber: error code to translate
% param[out]
%           error: error message


data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.system.errorNumberToString", "params": [%i], "id": 1, "api": 2}', errorNumber);

writeline(tcp, data_send);
data_receive = readline(tcp);
data = jsondecode(data_receive);

error = data.result(1);


end