classdef instrument_fournine < instrumentInterface
    % TCP client for the FourNine temperature-control service.

    properties (Access = private)
        readValues double = NaN
    end

    methods
        function obj = instrument_fournine(address, port)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText} = "127.0.0.1"
                port (1, 1) double {mustBeInteger, mustBePositive} = 5050
            end
            obj@instrumentInterface();

            handle = tcpclient(char(address), port);
            handle.Timeout = 10;
            configureTerminator(handle, "LF");

            obj.address = sprintf("%s:%d", address, port);
            obj.communicationHandle = handle;
            greeting = obj.readResponse("connect");
            if ~isfield(greeting, "data") || string(greeting.data) ~= "Temperature control API ready"
                error("instrument_fournine:UnexpectedGreeting", ...
                    "Unexpected FourNine greeting: %s", jsonencode(greeting));
            end

            obj.setTimeout = hours(6);
            obj.setInterval = seconds(10);

            obj.addChannel("T");
            obj.addChannel("T_target");
            obj.addChannel("heater");
            obj.addChannel("stable");
        end

        function currentTarget = getCurrentTargetTemperature(obj)
            currentTarget = obj.requireScalar(obj.query("GET_TARGET"), "GET_TARGET data");
        end

        function status = getStatus(obj)
            status = obj.query("GET_STATUS");
            obj.assertStatus(status, "GET_STATUS");
        end

        function startControl(obj)
            obj.assertStatus(obj.query("START_CONTROL"), "START_CONTROL");
        end

        function stopControl(obj)
            obj.assertStatus(obj.query("STOP_CONTROL"), "STOP_CONTROL");
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end

        function delete(obj)
            if ~isempty(obj.communicationHandle)
                tcp = obj.communicationHandle; %#ok<NASGU>
                obj.communicationHandle = [];
                clear tcp;
            end
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            status = obj.getStatus();
            switch channelIndex
                case 1
                    obj.readValues = obj.requireScalar(obj.statusField(status, "latest_temperature"), "latest_temperature");
                case 2
                    obj.readValues = obj.requireScalar(obj.statusField(status, "target"), "target");
                case 3
                    heater = obj.statusField(status, "latest_heater");
                    if isempty(heater) || ~isstruct(heater) || ~isfield(heater, "power")
                        error("instrument_fournine:NoHeaterData", ...
                            "GET_STATUS returned no latest_heater.power data.");
                    end
                    obj.readValues = obj.requireScalar(heater.power, "latest_heater.power");
                case 4
                    obj.readValues = double(obj.requireLogical(obj.statusField(status, "stable"), "stable"));
            end
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.readValues;
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    obj.query(sprintf("SET_TEMPERATURE %.15g", setValues));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    status = obj.getStatus();
                    target = obj.requireScalar(obj.statusField(status, "target"), "target");
                    if abs(target - channelLastSetValues) > 1e-3
                        error("instrument_fournine:TargetChanged", ...
                            "FourNine target changed during set check: expected %.15g K, current %.15g K.", ...
                            channelLastSetValues, target);
                    end
                    TF = channelLastSetValues == 0 ...
                        || obj.requireLogical(obj.statusField(status, "stable"), "stable");
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end
    end

    methods (Access = private)
        function data = query(obj, command)
            writeline(obj.communicationHandle, command);
            response = obj.readResponse(command);
            data = response.data;
        end

        function response = readResponse(obj, operation)
            raw = string(readline(obj.communicationHandle));
            try
                response = jsondecode(raw);
            catch ME
                error("instrument_fournine:MalformedJson", ...
                    "%s could not jsondecode response '%s': %s", operation, raw, string(ME.message));
            end

            if ~isstruct(response) || ~isfield(response, "ok") || isempty(response.ok) ...
                    || ~isscalar(response.ok) || ~(islogical(response.ok) || isnumeric(response.ok))
                error("instrument_fournine:MalformedResponse", ...
                    "%s returned malformed response: %s", operation, raw);
            end
            if ~response.ok
                if isfield(response, "error")
                    errorMessage = string(response.error);
                else
                    errorMessage = "missing error field";
                end
                error("instrument_fournine:CommandFailed", ...
                    "%s failed: %s. Raw response: %s", operation, errorMessage, raw);
            end
            if ~isfield(response, "data")
                error("instrument_fournine:MalformedResponse", ...
                    "%s response omitted data field: %s", operation, raw);
            end
        end

        function value = requireScalar(~, value, fieldName)
            if isempty(value) || ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
                error("instrument_fournine:MissingNumericData", ...
                    "FourNine response field %s must be a finite numeric scalar.", fieldName);
            end
            value = double(value);
        end

        function assertStatus(obj, status, operation)
            if isempty(status) || ~isstruct(status)
                error("instrument_fournine:MalformedStatus", ...
                    "%s returned status data that is not a struct.", operation);
            end
            if isfield(status, "last_error") && ~isempty(status.last_error) ...
                    && strlength(string(status.last_error)) > 0
                error("instrument_fournine:ServiceLoopError", ...
                    "%s reports last_error: %s", operation, string(status.last_error));
            end
            obj.statusField(status, "running");
            obj.statusField(status, "control_enabled");
            obj.statusField(status, "target");
            obj.statusField(status, "stable");
        end

        function value = statusField(~, status, fieldName)
            if ~isfield(status, fieldName)
                error("instrument_fournine:MissingStatusField", ...
                    "FourNine status response omitted required field %s.", fieldName);
            end
            value = status.(fieldName);
        end

        function value = requireLogical(~, value, fieldName)
            if isempty(value) || ~isscalar(value) || ~(islogical(value) || isnumeric(value))
                error("instrument_fournine:MissingLogicalData", ...
                    "FourNine response field %s must be a scalar logical or numeric value.", fieldName);
            end
            if isnumeric(value) && (~isfinite(value) || ~(value == 0 || value == 1))
                error("instrument_fournine:MissingLogicalData", ...
                    "FourNine response field %s must be logical, 0, or 1.", fieldName);
            end
            value = logical(value);
        end
    end
end
