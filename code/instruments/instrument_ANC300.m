classdef instrument_ANC300 < instrumentInterface
    % Direct USB-serial driver for Attocube ANC300.

    properties (Access = private)
        pendingValue double = NaN
        axisId_x (1, 1) double {mustBeInteger, mustBePositive} = 3
        axisId_y (1, 1) double {mustBeInteger, mustBePositive} = 4
        axisId_z (1, 1) double {mustBeInteger, mustBePositive} = 5
        stepRingdownDelay_s (1, 1) double {mustBeNonnegative} = 0.2
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

            obj.addChannel("voltage_x", setTolerances = 1e-3);
            obj.addChannel("voltage_y", setTolerances = 1e-3);
            obj.addChannel("voltage_z", setTolerances = 1e-3);
            obj.addChannel("frequency_x", setTolerances = 0.5);
            obj.addChannel("frequency_y", setTolerances = 0.5);
            obj.addChannel("frequency_z", setTolerances = 0.5);
        end

        function delete(obj)
            if isempty(obj.communicationHandle)
                return;
            end
            handle = obj.communicationHandle; %#ok<NASGU>
            obj.communicationHandle = [];
            clear handle;
        end

        function flush(obj)
            if isempty(obj.communicationHandle)
                return;
            end
            flush(obj.communicationHandle);
            obj.pendingValue = NaN;
        end

        function stepAxis(obj, axis, nSteps)
            arguments
                obj
                axis
                nSteps (1, 1) double {mustBeInteger, mustBeFinite}
            end

            axisId = obj.parseAxis(axis);
            obj.stepAxisIds(axisId, nSteps);
        end

        function stepXY(obj, nStepsX, nStepsY)
            arguments
                obj
                nStepsX (1, 1) double {mustBeInteger, mustBeFinite}
                nStepsY (1, 1) double {mustBeInteger, mustBeFinite}
            end

            obj.stepAxisIds([obj.axisId_x, obj.axisId_y], [nStepsX, nStepsY]);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            obj.pendingValue = obj.queryChannelValue(channelIndex);
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
                    frequency_Hz = obj.prepareFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_x, frequency_Hz));
                case 5
                    frequency_Hz = obj.prepareFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_y, frequency_Hz));
                case 6
                    frequency_Hz = obj.prepareFrequency(value);
                    obj.writeCommand(sprintf("setf %d %d", obj.axisId_z, frequency_Hz));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            actualValue = obj.queryChannelValue(channelIndex);
            expectedValue = channelLastSetValues(1);
            if channelIndex >= 4 && channelIndex <= 6
                expectedValue = obj.prepareFrequency(expectedValue);
            end
            TF = abs(actualValue - expectedValue) <= obj.setTolerances{channelIndex};
            if ~TF
                error("instrument_ANC300:SetCheckFailed", ...
                    "ANC300 %s set-check failed: expected %.9g, actual %.9g, tolerance %.3g.", ...
                    obj.channelTable.channels(channelIndex), expectedValue, actualValue, obj.setTolerances{channelIndex});
            end
        end
    end

    methods (Access = private)
        function value = queryChannelValue(obj, channelIndex)
            switch channelIndex
                case 1
                    value = obj.queryScalar(sprintf("getv %d", obj.axisId_x));
                case 2
                    value = obj.queryScalar(sprintf("getv %d", obj.axisId_y));
                case 3
                    value = obj.queryScalar(sprintf("getv %d", obj.axisId_z));
                case 4
                    value = obj.queryScalar(sprintf("getf %d", obj.axisId_x));
                case 5
                    value = obj.queryScalar(sprintf("getf %d", obj.axisId_y));
                case 6
                    value = obj.queryScalar(sprintf("getf %d", obj.axisId_z));
                otherwise
                    error("instrument_ANC300:UnsupportedGetChannel", ...
                        "Unsupported channel index %d.", channelIndex);
            end
        end

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

        function stepAxisIds(obj, axisIds, nSteps)
            axisIds = double(axisIds(:).');
            nSteps = double(nSteps(:).');
            if numel(axisIds) ~= numel(nSteps)
                error("instrument_ANC300:StepArgumentMismatch", ...
                    "Axis ID and step count lists must have the same length.");
            end

            activeMask = nSteps ~= 0;
            if ~any(activeMask)
                return;
            end
            axisIds = axisIds(activeMask);
            nSteps = nSteps(activeMask);
            stepCounts = abs(nSteps);
            frequencies_Hz = NaN(size(axisIds));
            for stepIndex = 1:numel(axisIds)
                frequencies_Hz(stepIndex) = obj.queryScalar(sprintf("getf %d", axisIds(stepIndex)));
                obj.assertValidFrequency(frequencies_Hz(stepIndex));
            end

            handle = obj.communicationHandle;
            originalTimeout = handle.Timeout;
            handle.Timeout = max(originalTimeout, max(stepCounts ./ frequencies_Hz) + 5);
            try
                for stepIndex = 1:numel(axisIds)
                    if nSteps(stepIndex) > 0
                        stepCommand = "stepu";
                    else
                        stepCommand = "stepd";
                    end
                    obj.writeCommand(sprintf("%s %d %d", stepCommand, axisIds(stepIndex), stepCounts(stepIndex)));
                end
                for stepIndex = 1:numel(axisIds)
                    obj.writeCommand(sprintf("stepw %d", axisIds(stepIndex)));
                end
                pause(obj.stepRingdownDelay_s);
            catch exception
                handle.Timeout = originalTimeout;
                rethrow(exception);
            end
            handle.Timeout = originalTimeout;
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

        function frequency_Hz = prepareFrequency(obj, value)
            obj.assertValidFrequency(value);
            frequency_Hz = round(value);
        end

        function writeCommand(obj, command)
            handle = obj.communicationHandle;
            obj.flush();
            writeline(handle, command);
            responseLines = obj.readCommandResponse(command);
            if ~isempty(responseLines)
                error("instrument_ANC300:UnexpectedResponse", ...
                    "Unexpected ANC300 response for ""%s"": %s", command, strjoin(responseLines, " | "));
            end
        end

        function responseLine = queryCommand(obj, command)
            handle = obj.communicationHandle;
            obj.flush();
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
                lines = obj.readProtocolLines(command, responseLines(1:responseCount));
                for line = reshape(lines, 1, [])
                    if strcmp(line, "") || strcmp(line, ">") || strcmp(line, string(command))
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
        end

        function lines = readProtocolLines(obj, command, responseLines)
            try
                rawLine = string(readline(obj.communicationHandle));
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
            if isempty(rawLine) || ~isscalar(rawLine) || ismissing(rawLine)
                if isempty(responseLines)
                    lastResponse = "<none>";
                else
                    lastResponse = strjoin(responseLines, " | ");
                end
                error("instrument_ANC300:Timeout", ...
                    "Timed out waiting for ANC300 response to ""%s"". Last response: %s", ...
                    command, lastResponse);
            end
            rawLine = replace(rawLine, sprintf("\r\n"), newline);
            rawLine = replace(rawLine, sprintf("\r"), newline);
            lines = strip(splitlines(rawLine));
            for lineIndex = 1:numel(lines)
                if startsWith(lines(lineIndex), ">")
                    lines(lineIndex) = strip(extractAfter(lines(lineIndex), 1));
                end
            end
        end
    end
end
