classdef instrument_HP34401A < instrumentInterface
    % HP 34401A digital multimeter (GPIB via visadev)

    methods

        function obj = instrument_HP34401A(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("value");
        end

        function reset(obj)
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            writeline(handle, ":CONF:VOLT:DC");
            writeline(handle, ":VOLT:DC:NPLC 0.5");
        end

        function flush(obj)
            % Trigger one-time auto-zero and flush communication buffer.
            writeline(obj.communicationHandle, ":ZERO:AUTO ONCE");
            flush(obj.communicationHandle);
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
                    writeline(handle, "READ?");
            end
        end

        function getValues = getReadChannelHelper(obj, ~)
            handle = obj.communicationHandle;
            getValues = str2double(strip(readline(handle)));
        end

    end

end
