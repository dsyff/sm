function reprogramSTServoId(comPort, idFrom, idTo, NameValueArgs)
%reprogramSTServoId Convenience wrapper (no class instance needed).
%
% This forwards to the static utility:
%   instrument_ST3215HS.reprogramSTServoId(...)
%
% Usage:
%   reprogramSTServoId("COM3", 1, 2);
%   reprogramSTServoId("COM3", 1, 2, baudRate=1000000, timeoutSeconds=0.2);

arguments
    comPort (1, 1) string {mustBeNonzeroLengthText}
    idFrom (1, 1) double {mustBeInteger, mustBePositive}
    idTo (1, 1) double {mustBeInteger, mustBePositive}
    NameValueArgs.baudRate (1, 1) double {mustBePositive, mustBeInteger} = 1000000
    NameValueArgs.timeoutSeconds (1, 1) double {mustBePositive} = 0.2
    NameValueArgs.verbose (1, 1) logical = true
end

instrument_ST3215HS.reprogramSTServoId(comPort, idFrom, idTo, ...
    baudRate = NameValueArgs.baudRate, ...
    timeoutSeconds = NameValueArgs.timeoutSeconds, ...
    verbose = NameValueArgs.verbose);

end


