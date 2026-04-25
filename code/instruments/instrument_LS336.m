classdef instrument_LS336 < instrumentInterface
    % Lake Shore Model 336 temperature controller.

    properties (Access = private)
        temperatureInputs = ["A", "B", "C", "D"];
    end

    methods

        function obj = instrument_LS336(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;
            obj.setTimeout = hours(2);
            obj.setInterval = seconds(10);

            obj.addChannel("KRDG_A");
            obj.addChannel("KRDG_B");
            obj.addChannel("KRDG_C");
            obj.addChannel("KRDG_D");
            obj.addChannel("SETP_1", setTolerances = 0.1);
            obj.addChannel("SETP_2", setTolerances = 0.1);
            obj.addChannel("SETP_3", setTolerances = 0.1);
            obj.addChannel("SETP_4", setTolerances = 0.1);
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            if handle.NumBytesAvailable > 0
                flush(handle);
            end

            if channelIndex <= 4
                writeline(handle, "KRDG? " + lower(obj.temperatureInputs(channelIndex)));
            else
                writeline(handle, sprintf("SETP? %d", channelIndex - 4));
            end
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.readNumericResponse();
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex < 5
                setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
                return;
            end

            outputIndex = channelIndex - 4;
            writeline(obj.communicationHandle, sprintf("SETP %d,%g", outputIndex, setValues));
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            outputIndex = channelIndex - 4;
            handle = obj.communicationHandle;
            if handle.NumBytesAvailable > 0
                flush(handle);
            end

            if channelLastSetValues == 0
                writeline(handle, sprintf("SETP? %d", outputIndex));
            else
                writeline(handle, "KRDG? " + lower(obj.temperatureInputs(outputIndex)));
            end
            readback = obj.readNumericResponse();
            TF = abs(readback - channelLastSetValues) <= obj.setTolerances{channelIndex};
        end

    end

    methods (Access = private)

        function value = readNumericResponse(obj)
            response = strip(readline(obj.communicationHandle));
            value = str2double(response);
            if isnan(value)
                error("instrument_LS336:UnexpectedResponse", ...
                    "Expected numeric LS336 response, got '%s'.", response);
            end
        end

    end

end
