classdef instrument_K2400 < instrumentInterface
    % Thomas 20250103
    % only for sourcing voltage and measuring current
    properties
        % used to determine if voltage has been reached
        chargeCurrentLimit double {mustBePositive} = inf;
    end

    methods

        function obj = instrument_K2400(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF")
            obj.writeCommandInterval = seconds(0.4);

            % assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("V_source", setTolerances = 5E-4);
            obj.addChannel("I_measure");
            obj.addChannel("VI", 2);
        end


        function reset(obj)
            handle = obj.communicationHandle;
            writeline(handle,"*RST");
            writeline(handle, ":FORMat:ELEMents VOLTage,CURRent");
            writeline(handle, ":OUTPut ON");
        end

        function flush(obj)
            % Trigger one-time auto-zero and flush communication buffer.
            writeline(obj.communicationHandle, ":SYSTem:AZERo:STATe ONCE");
            flush(obj.communicationHandle);
        end
    end
    
    methods (Access = ?instrumentInterface)

        % channelIndex are in the order that the channels are added,
        % starting from 1
        function getWriteChannelHelper(obj, ~)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end
            writeline(handle, ":READ?");
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

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    writeline(handle, sprintf(":SOURce:VOLTage %g", setValues));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            % channels other than 1 will be rejected by setCheckChannel
            switch channelIndex
                case 1
                    handle = obj.communicationHandle;
                    writeline(handle, ":READ?");
                    outputValues = str2double(split(strip(readline(handle)), ","));
                    getValues = outputValues(1);
                    current = outputValues(2);
                    TF = all(abs(getValues - channelLastSetValues) <= obj.setTolerances{channelIndex});
                    TF = TF && abs(current) < obj.chargeCurrentLimit;
            end
        end

    end

end