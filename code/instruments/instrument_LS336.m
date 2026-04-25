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

            obj.addChannel("T_A", setTolerances = 0.1);
            obj.addChannel("T_B", setTolerances = 0.1);
            obj.addChannel("T_C", setTolerances = 0.1);
            obj.addChannel("T_D", setTolerances = 0.1);
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end

        function cooldown(obj)
            obj.setOutputOneAndTwo(0);
        end

        function warmup(obj)
            obj.setOutputOneAndTwo(300);
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end

            writeline(handle, "KRDG? " + lower(obj.temperatureInputs(channelIndex)));
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.readNumericResponse();
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            writeline(obj.communicationHandle, sprintf("SETP %d,%g", channelIndex, setValues));
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end

            if channelLastSetValues == 0
                writeline(handle, sprintf("SETP? %d", channelIndex));
            else
                writeline(handle, "KRDG? " + lower(obj.temperatureInputs(channelIndex)));
            end
            readback = obj.readNumericResponse();
            TF = abs(readback - channelLastSetValues) <= obj.setTolerances{channelIndex};
        end

    end

    methods (Access = private)

        function setOutputOneAndTwo(obj, target_K)
            for outputIndex = 1:2
                writeline(obj.communicationHandle, sprintf("SETP %d,%g", outputIndex, target_K));
            end
        end

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
