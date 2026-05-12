classdef instrument_TM620 < instrumentInterface
    % Model TM-620 temperature monitor.

    properties (Access = private)
        subchannels = ["A", "B"];
    end

    methods

        function obj = instrument_TM620(address)
            obj@instrumentInterface();
            handle = serialport(address, 9600, Timeout = 1);

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("MEAS_A");
            obj.addChannel("MEAS_B");
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            subchannel = obj.subchannels(channelIndex);
            flush(handle);
            writeline(handle, "SUBCH " + subchannel);
            readline(handle);
            flush(handle);
            writeline(handle, "MEAS?");
            readline(handle);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            response = strip(readline(obj.communicationHandle));
            subchannel = obj.subchannels(channelIndex);
            tokens = regexp(response, "^\s*" + subchannel + ":\s*([+-]?\d+(?:\.\d*)?(?:[Ee][+-]?\d+)?)\s*K\s*$", "tokens", "once");
            if isempty(tokens)
                error("instrument_TM620:UnexpectedResponse", ...
                    "Expected TM620 %s temperature response, got '%s'.", subchannel, response);
            end
            getValues = str2double(tokens{1});
        end

    end

end
