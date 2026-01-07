function tcp = connect(IP)

% brief : This function initializes and connects a selected device.
%
% param[in] IP : IP connection of the Device
%
% param[out] tcp : TCP/IP connection ID, a tcpclient object 

arguments
    IP (1, 1) string {mustBeNonzeroLengthText}
end

tcp = tcpclient(char(IP), 9090);

end