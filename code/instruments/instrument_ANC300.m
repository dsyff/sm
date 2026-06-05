classdef instrument_ANC300 < instrumentInterface
    % Direct USB-serial driver for Attocube ANC300.

    properties (Access = private)
        pendingValue double = NaN
        axisId_x (1, 1) double {mustBeInteger, mustBePositive} = 3
        axisId_y (1, 1) double {mustBeInteger, mustBePositive} = 4
        axisId_z (1, 1) double {mustBeInteger, mustBePositive} = 5
    end

    methods
        function obj = instrument_ANC300(address)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
            end

            obj@instrumentInterface();
            obj.address = address;

            handle = serialport(address, 38400, Timeout = 2);
            configureTerminator(handle, "CR/LF");
            flush(handle);
            obj.communicationHandle = handle;

            versionText = obj.queryCommand("ver");
            if ~contains(lower(versionText), "attocube anc300")
                error("instrument_ANC300:UnexpectedDevice", ...
                    "Expected Attocube ANC300 at %s, received: %s", address, versionText);
            end
            obj.writeCommand("echo off");

            for axisId = [obj.axisId_x, obj.axisId_y, obj.axisId_z]
                obj.writeCommand(sprintf("setm %d stp", axisId));
                obj.writeCommand(sprintf("setf %d %d", axisId, 50));
            end

            obj.addChannel("voltage_x");
            obj.addChannel("voltage_y");
            obj.addChannel("voltage_z");
            obj.addChannel("frequency_x");
            obj.addChannel("frequency_y");
            obj.addChannel("frequency_z");
        end

        function delete(obj)
            if isempty(obj.communicationHandle)
                return;
            end
            handle = obj.communicationHandle; %#ok<NASGU>
            obj.communicationHandle = [];
            clear handle;
        end

        function stepAxis(obj, axis, nSteps)
            arguments
                obj
                axis
                nSteps (1, 1) double {mustBeInteger}
            end

            axisId = obj.parseAxis(axis);
            if nSteps == 0
                return;
            end
            if nSteps > 0
                obj.writeCommand(sprintf("stepu %d %d", axisId, nSteps));
            else
                obj.writeCommand(sprintf("stepd %d %d", axisId, -nSteps));
            end
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", obj.axisId_x));
                case 2
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", obj.axisId_y));
                case 3
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", obj.axisId_z));
                case 4
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", obj.axisId_x));
                case 5
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", obj.axisId_y));
                case 6
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", obj.axisId_z));
                otherwise
                    error("instrument_ANC300:UnsupportedGetChannel", ...
                        "Unsupported get channel index %d.", channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.pendingValue;
            obj.pendingValue = NaN;
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            value = setValues(1);
            switch channelIndex
                case 1
                    obj.assertFiniteVoltage(value);
                    obj.writeCommand(sprintf("setv %d %.9g", obj.axisId_x, value));
                case 2
                    obj.assertFiniteVoltage(value);
                    obj.writeCommand(sprintf("setv %d %.9g", obj.axisId_y, value));
                case 3
                    obj.assertFiniteVoltage(value);
                    obj.writeCommand(sprintf("setv %d %.9g", obj.axisId_z, value));
                case 4
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_x, round(value)));
                case 5
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_y, round(value)));
                case 6
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_z, round(value)));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end
    end

    methods (Access = private)
        function axisId = parseAxis(obj, axis)
            if isnumeric(axis)
                axisIds = [obj.axisId_z, obj.axisId_y, obj.axisId_x];
                if ~(isscalar(axis) && isfinite(axis) && axis == round(axis) && any(axis == axisIds))
                    error("instrument_ANC300:InvalidAxisId", ...
                        "Axis ID must be one of z=%d, y=%d, or x=%d.", ...
                        obj.axisId_z, obj.axisId_y, obj.axisId_x);
                end
                axisId = double(axis);
                return;
            end

            axisName = lower(string(axis));
            if axisName == "x"
                axisId = obj.axisId_x;
            elseif axisName == "y"
                axisId = obj.axisId_y;
            elseif axisName == "z"
                axisId = obj.axisId_z;
            else
                error("instrument_ANC300:InvalidAxisName", ...
                    "Axis must be ""x"", ""y"", ""z"", or configured numeric ID.");
            end
        end

        function assertFiniteVoltage(~, value)
            if ~isfinite(value) || value < 0 || value > 60
                error("instrument_ANC300:InvalidVoltage", ...
                    "Voltage must be finite and within [0, 60] V. Received %g.", value);
            end
        end

        function assertValidFrequency(~, value)
            if ~isfinite(value) || value < 1 || value > 10000
                error("instrument_ANC300:InvalidFrequency", ...
                    "Frequency must be finite and within [1, 10000] Hz. Received %g.", value);
            end
        end

        function writeCommand(obj, command)
            handle = obj.communicationHandle;
            writeline(handle, command);
            responseLines = obj.readCommandResponse(command);
            if ~isempty(responseLines)
                error("instrument_ANC300:UnexpectedResponse", ...
                    "Unexpected ANC300 response for ""%s"": %s", command, strjoin(responseLines, " | "));
            end
        end

        function responseLine = queryCommand(obj, command)
            handle = obj.communicationHandle;
            writeline(handle, command);
            responseLines = obj.readCommandResponse(command);
            if isempty(responseLines)
                error("instrument_ANC300:UnexpectedResponse", ...
                    "ANC300 query ""%s"" returned OK without data.", command);
            end
            responseLine = strjoin(responseLines, " | ");
        end

        function value = queryScalar(obj, command)
            responseLine = obj.queryCommand(command);

            if contains(responseLine, "=")
                responseLine = strip(extractAfter(responseLine, "="));
            end
            responseTokens = split(strip(responseLine));
            value = str2double(responseTokens(1));
            if ~isfinite(value)
                error("instrument_ANC300:ParseError", ...
                    "Could not parse scalar response for ""%s"": %s", command, responseLine);
            end
        end

        function responseLines = readCommandResponse(obj, command)
            responseLines = strings(512, 1);
            responseCount = 0;
            while true
                line = obj.readProtocolLine(command, responseLines(1:responseCount));
                if line == "" || line == ">" || line == command
                    continue;
                end
                if startsWith(line, "OK")
                    responseLines = responseLines(1:responseCount);
                    return;
                end
                if startsWith(line, "ERROR")
                    if responseCount == 0
                        detail = line;
                    else
                        detail = strjoin([responseLines(1:responseCount); line], " | ");
                    end
                    error("instrument_ANC300:CommandFailed", ...
                        "ANC300 command ""%s"" failed: %s", command, detail);
                end
                responseCount = responseCount + 1;
                if responseCount > numel(responseLines)
                    error("instrument_ANC300:UnexpectedResponse", ...
                        "ANC300 response to ""%s"" exceeded %d lines.", command, numel(responseLines));
                end
                responseLines(responseCount) = line;
            end
        end

        function line = readProtocolLine(obj, command, responseLines)
            try
                line = strip(string(readline(obj.communicationHandle)));
            catch
                if isempty(responseLines)
                    lastResponse = "<none>";
                else
                    lastResponse = strjoin(responseLines, " | ");
                end
                error("instrument_ANC300:Timeout", ...
                    "Timed out waiting for ANC300 response to ""%s"". Last response: %s", ...
                    command, lastResponse);
            end
            if startsWith(line, ">")
                line = strip(extractAfter(line, 1));
            end
        end
    end
end
