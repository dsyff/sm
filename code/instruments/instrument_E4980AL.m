classdef instrument_E4980AL < instrumentInterface
    % Thomas 20250115
    % exclusively for measuring strain cell capacitance displacement sensor

    methods

        function obj = instrument_E4980AL(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");
            writeline(handle, ":FUNC:IMP CPQ"); % measure in CPQ mode
            writeline(handle, ":FREQ 1E5"); % measure at 100kHz
            writeline(handle, ":VOLT 2"); % measure with 2V ac
            writeline(handle, ":APER MED"); % sets averaging time to medium
            writeline(handle, ":DISP:ENAB OFF"); % turns off display update
            writeline(handle, ":DISP:ENAB?");
            readline(handle);

            % assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("Cp");
            obj.addChannel("Q");
            obj.addChannel("CpQ", 2);
        end

        function flush(obj)
            % Flush communication buffer
            flush(obj.communicationHandle);
        end
        
    end
    
    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, ~)
            handle = obj.communicationHandle;
            flush(handle);
            writeline(handle, ":FETC?");
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            outputValues = str2double(split(strip(readline(handle)), ","));
            switch channelIndex
                case 1
                    getValues = outputValues(1);
                case 2
                    getValues = outputValues(2);
                case 3
                    getValues = outputValues(1:2);
            end
        end

    end

end