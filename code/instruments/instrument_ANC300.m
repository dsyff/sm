classdef instrument_ANC300 < instrumentInterface
    % Direct USB-serial driver for Attocube ANC300.

    properties (Access = private)
        pendingValue double = NaN
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

            for axisId = 1:3
                obj.writeCommand(sprintf("setm %d stp", axisId));
                obj.writeCommand(sprintf("setf %d %d", axisId, 100));
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
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", 3)); % x -> axis 3
                case 2
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", 2)); % y -> axis 2
                case 3
                    obj.pendingValue = obj.queryScalar(sprintf("getv %d", 1)); % z -> axis 1
                case 4
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", 3)); % x -> axis 3
                case 5
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", 2)); % y -> axis 2
                case 6
                    obj.pendingValue = obj.queryScalar(sprintf("getf %d", 1)); % z -> axis 1
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
                    obj.writeCommand(sprintf("setv %d %.9g", 3, value)); % x -> axis 3
                case 2
                    obj.assertFiniteVoltage(value);
                    obj.writeCommand(sprintf("setv %d %.9g", 2, value)); % y -> axis 2
                case 3
                    obj.assertFiniteVoltage(value);
                    obj.writeCommand(sprintf("setv %d %.9g", 1, value)); % z -> axis 1
                case 4
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", 3, round(value))); % x -> axis 3
                case 5
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", 2, round(value))); % y -> axis 2
                case 6
                    obj.assertValidFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", 1, round(value))); % z -> axis 1
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end
    end

    methods (Access = private)
        function axisId = parseAxis(~, axis)
            if isnumeric(axis)
                if ~(isscalar(axis) && isfinite(axis) && axis == round(axis) && any(axis == [1, 2, 3]))
                    error("instrument_ANC300:InvalidAxisId", ...
                        "Axis ID must be 1 (z), 2 (y), or 3 (x).");
                end
                axisId = double(axis);
                return;
            end

            axisName = lower(string(axis));
            if axisName == "x"
                axisId = 3;
            elseif axisName == "y"
                axisId = 2;
            elseif axisName == "z"
                axisId = 1;
            else
                error("instrument_ANC300:InvalidAxisName", ...
                    "Axis must be ""x"", ""y"", ""z"", or numeric ID 1/2/3.");
            end
        end

        function assertFiniteVoltage(~, value)
            if ~isfinite(value)
                error("instrument_ANC300:InvalidVoltage", ...
                    "Voltage must be finite. Received %g.", value);
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

            firstLine = obj.readProtocolLine();
            if firstLine == command
                firstLine = obj.readProtocolLine();
            end

            if startsWith(firstLine, "OK")
                return;
            end
            if startsWith(firstLine, "ERROR")
                error("instrument_ANC300:CommandFailed", ...
                    "ANC300 command failed: %s", firstLine);
            end

            secondLine = obj.readProtocolLine();
            if startsWith(secondLine, "ERROR")
                error("instrument_ANC300:CommandFailed", ...
                    "ANC300 command failed: %s", firstLine);
            end
            if ~startsWith(secondLine, "OK")
                error("instrument_ANC300:UnexpectedResponse", ...
                    "Unexpected ANC300 response for ""%s"": %s | %s", command, firstLine, secondLine);
            end
        end

        function responseLine = queryCommand(obj, command)
            handle = obj.communicationHandle;
            writeline(handle, command);

            responseLine = obj.readProtocolLine();
            if responseLine == command
                responseLine = obj.readProtocolLine();
            end

            statusLine = obj.readProtocolLine();
            if startsWith(statusLine, "OK")
                return;
            end
            if startsWith(statusLine, "ERROR")
                error("instrument_ANC300:CommandFailed", ...
                    "ANC300 query failed: %s", responseLine);
            end

            responseLine = responseLine + " - " + statusLine;
            finalStatus = obj.readProtocolLine();
            if startsWith(finalStatus, "ERROR")
                error("instrument_ANC300:CommandFailed", ...
                    "ANC300 query failed: %s", responseLine);
            end
            if ~startsWith(finalStatus, "OK")
                error("instrument_ANC300:UnexpectedResponse", ...
                    "Unexpected ANC300 status for ""%s"": %s", command, finalStatus);
            end
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

        function line = readProtocolLine(obj)
            line = strip(string(readline(obj.communicationHandle)));
            if startsWith(line, "> ")
                line = extractAfter(line, 2);
            end
        end
    end
end
