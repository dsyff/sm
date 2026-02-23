classdef instrument_USB6001 < instrumentInterface
    properties (Access = private)
        AI_values (:, 1) double = NaN(1, 1);
        AO_values (2, 1) double = zeros(2, 1);
        numAIChannels (1, 1) double = 1;
        integrationTime_s (1, 1) double = 0;
        samplingRate_Hz (1, 1) double = 2E4;
        acquisitionPending (1, 1) logical = false;
        scansPerAcquisition (1, 1) double = 1;
    end

    methods
        function obj = instrument_USB6001(address, numAIChannels)
            arguments
                address (1, 1) string = "Dev1";
                numAIChannels (1, 1) double {mustBeInteger, mustBePositive} = 1;
            end
            if numAIChannels > 8
                error("instrument_USB6001:InvalidNumAIChannels", ...
                    "numAIChannels must be between 1 and 8.");
            end

            obj@instrumentInterface();
            obj.requireSetCheck = false;
            obj.numAIChannels = numAIChannels;
            obj.AI_values = NaN(numAIChannels, 1);
            obj.samplingRate_Hz = min(2E4 / numAIChannels, 5E3);

            handle = daq("ni");
            for inputIndex = 0:numAIChannels-1
                addinput(handle, address, "ai" + string(inputIndex), "Voltage");
            end
            for outputIndex = 0:1
                addoutput(handle, address, "ao" + string(outputIndex), "Voltage");
            end
            handle.Rate = obj.samplingRate_Hz;
            flush(handle);

            obj.address = address;
            obj.communicationHandle = handle;

            for inputIndex = 0:numAIChannels-1
                obj.addChannel("AI" + string(inputIndex));
            end
            if numAIChannels > 1
                aiVectorChannelName = "AI" + join(string(0:numAIChannels-1), "");
                obj.addChannel(aiVectorChannelName, uint64(numAIChannels));
            end
            obj.addChannel("AO0");
            obj.addChannel("AO1");
            obj.addChannel("integration_time_s");
            obj.addChannel("sampling_rate_Hz");
        end

        function delete(obj)
            if isempty(obj.communicationHandle)
                return;
            end
            if obj.acquisitionPending
                stop(obj.communicationHandle);
                obj.acquisitionPending = false;
            end
            flush(obj.communicationHandle);
        end

        function flush(obj)
            if obj.acquisitionPending
                stop(obj.communicationHandle);
                obj.acquisitionPending = false;
            end
            flush(obj.communicationHandle);
            obj.AI_values = NaN(obj.numAIChannels, 1);
            obj.scansPerAcquisition = 1;
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            channelName = obj.channelTable.channels(channelIndex);
            if startsWith(channelName, "AI") && ~obj.acquisitionPending
                obj.scansPerAcquisition = max(1, ceil(obj.integrationTime_s * obj.samplingRate_Hz));
                flush(obj.communicationHandle);
                start(obj.communicationHandle, "continuous");
                obj.acquisitionPending = true;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            channelName = obj.channelTable.channels(channelIndex);
            switch channelName
                case {"AO0", "AO1"}
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set AO channels while acquisition is pending. Complete the read or call flush().");
                    end
                    aoIndex = str2double(extractAfter(channelName, "AO")) + 1;
                    obj.AO_values(aoIndex) = setValues(1);
                    write(obj.communicationHandle, obj.AO_values.');
                case "integration_time_s"
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set integration_time_s while acquisition is pending. Complete the read or call flush().");
                    end
                    value = setValues(1);
                    if value < 0
                        error("instrument_USB6001:InvalidIntegrationTime", ...
                            "integration_time_s must be greater than or equal to 0.");
                    end
                    obj.integrationTime_s = value;
                case "sampling_rate_Hz"
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set sampling_rate_Hz while acquisition is pending. Complete the read or call flush().");
                    end
                    value = setValues(1);
                    if value <= 0
                        error("instrument_USB6001:InvalidSamplingRate", ...
                            "sampling_rate_Hz must be greater than 0.");
                    end
                    maxRate_Hz = min(2E4 / obj.numAIChannels, 5E3);
                    if value > maxRate_Hz
                        error("instrument_USB6001:SamplingRateTooHigh", ...
                            "sampling_rate_Hz must be less than or equal to %.15g for numAIChannels=%d.", ...
                            maxRate_Hz, obj.numAIChannels);
                    end
                    obj.samplingRate_Hz = value;
                    obj.communicationHandle.Rate = value;
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            channelName = obj.channelTable.channels(channelIndex);
            if startsWith(channelName, "AI")
                if obj.acquisitionPending
                    data = read(obj.communicationHandle, obj.scansPerAcquisition, "OutputFormat", "Matrix");
                    stop(obj.communicationHandle);
                    obj.acquisitionPending = false;
                    obj.AI_values = mean(data, 1).';
                end

                if obj.channelTable.channelSizes(channelIndex) == 1
                    aiIndex = str2double(extractAfter(channelName, "AI")) + 1;
                    getValues = obj.AI_values(aiIndex);
                else
                    getValues = obj.AI_values;
                end
                return;
            end

            switch channelName
                case "AO0"
                    getValues = obj.AO_values(1);
                case "AO1"
                    getValues = obj.AO_values(2);
                case "integration_time_s"
                    getValues = obj.integrationTime_s;
                case "sampling_rate_Hz"
                    getValues = obj.samplingRate_Hz;
                otherwise
                    error("instrument_USB6001:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
        end
    end
end
