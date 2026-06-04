function errorNumber = action_goToBase(tcp)
% action_goToBase
% brief : Cool down to base temperature

data_send = sprintf('{"jsonrpc": "2.0", "method": "com.attocube.cryostat.interface.action.goToBase", "params": [], "id": 1, "api": 2}');

writeline(tcp, data_send);
data_receive = readline(tcp);

% Thomas edit (sm-dev): vendor wrapper made robust via attoDRY_parseResult
errorNumber = attoDRY_parseResult(data_receive, 1, "action_goToBase");


end
