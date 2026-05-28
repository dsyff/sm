classdef instrument_4GMPS < instrumentInterface
    % Cryomagnetics 4G magnet power supply. B is exposed in tesla.

    methods

        function obj = instrument_4GMPS(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;
            obj.setTimeout = hours(2);
            obj.setInterval = seconds(3);

            obj.addChannel("B", setTolerances = 1E-2);
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end

        function sweepPause(obj)
            writeline(obj.communicationHandle, "SWEEP PAUSE");
        end

        function sweepZero(obj)
            writeline(obj.communicationHandle, "SWEEP ZERO");
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, ~)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end

            writeline(handle, "IMAG?");
        end

        function getValues = getReadChannelHelper(obj, ~)
            response = strip(readline(obj.communicationHandle));
            getValues = obj.parseFieldTesla(response);
        end

        function setWriteChannelHelper(obj, ~, setValues)
            handle = obj.communicationHandle;
            currentField_T = obj.readFieldTesla();
            if setValues >= currentField_T
                writeline(handle, sprintf("ULIM %g", 10 * setValues));
                writeline(handle, "SWEEP UP");
            else
                writeline(handle, sprintf("LLIM %g", 10 * setValues));
                writeline(handle, "SWEEP DOWN");
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            readback = obj.readFieldTesla();
            TF = abs(readback - channelLastSetValues) <= obj.setTolerances{channelIndex};
        end

    end

    methods (Access = private)

        function field_T = readFieldTesla(obj)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end
            writeline(handle, "IMAG?");
            field_T = obj.parseFieldTesla(strip(readline(handle)));
        end

        function field_T = parseFieldTesla(~, response)
            tokens = regexp(response, "^\s*([+-]?\d+(?:\.\d*)?(?:[Ee][+-]?\d+)?)\s*([A-Za-z]+)\s*$", "tokens", "once");
            if isempty(tokens)
                error("instrument_4GMPS:UnexpectedResponse", ...
                    "Expected 4GMPS field response with units, got '%s'.", response);
            end

            value = str2double(tokens{1});
            unit = upper(string(tokens{2}));
            switch unit
                case "KG"
                    field_T = value / 10;
                case "G"
                    field_T = value / 10000;
                case "T"
                    field_T = value;
                case "A"
                    error("instrument_4GMPS:UnexpectedUnits", ...
                        "4GMPS returned amps. Configure the supply to field units before using the B channel.");
                otherwise
                    error("instrument_4GMPS:UnexpectedUnits", ...
                        "Unsupported 4GMPS field unit '%s'.", unit);
            end
        end

    end

end
