classdef instrument_4GMPS < instrumentInterface
    % Cryomagnetics 4G magnet power supply. Field channels use tesla.

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

            obj.addChannel("IMAG", setTolerances = 1E-2);
            obj.addChannel("VMAG");
            obj.addChannel("ULIM", setTolerances = 1E-3);
            obj.addChannel("LLIM", setTolerances = 1E-3);
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

        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end

            switch channelIndex
                case 1
                    writeline(handle, "IMAG?");
                case 2
                    writeline(handle, "VMAG?");
                case 3
                    writeline(handle, "ULIM?");
                case 4
                    writeline(handle, "LLIM?");
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            response = strip(readline(obj.communicationHandle));
            if channelIndex == 2
                tokens = regexp(response, "^\s*([+-]?\d+(?:\.\d*)?(?:[Ee][+-]?\d+)?)\s*V\s*$", "tokens", "once");
                if isempty(tokens)
                    error("instrument_4GMPS:UnexpectedResponse", ...
                        "Expected 4GMPS voltage response, got '%s'.", response);
                end
                getValues = str2double(tokens{1});
            else
                getValues = obj.parseFieldTesla(response);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    currentField_T = obj.readFieldTesla();
                    if setValues >= currentField_T
                        writeline(handle, sprintf("ULIM %g", 10 * setValues));
                        writeline(handle, "SWEEP UP");
                    else
                        writeline(handle, sprintf("LLIM %g", 10 * setValues));
                        writeline(handle, "SWEEP DOWN");
                    end
                case 3
                    writeline(handle, sprintf("ULIM %g", 10 * setValues));
                case 4
                    writeline(handle, sprintf("LLIM %g", 10 * setValues));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    readback = obj.readFieldTesla();
                case 3
                    readback = obj.readLimitTesla("ULIM?");
                case 4
                    readback = obj.readLimitTesla("LLIM?");
            end
            TF = abs(readback - channelLastSetValues) <= obj.setTolerances{channelIndex};
        end

    end

    methods (Access = private)

        function field_T = readFieldTesla(obj)
            field_T = obj.readLimitTesla("IMAG?");
        end

        function field_T = readLimitTesla(obj, command)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end
            writeline(handle, command);
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
