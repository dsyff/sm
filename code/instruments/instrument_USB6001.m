classdef instrument_USB6001 < instrumentInterface
    properties (Access = private)
        AI_values (:, 1) double = NaN(1, 1);
        AO_values (2, 1) double = zeros(2, 1);
        numAIChannels (1, 1) double = 1;
        aiVectorChannelIndex (1, 1) double = 0;
        ao0ChannelIndex (1, 1) double = 0;
        ao1ChannelIndex (1, 1) double = 0;
        integrationChannelIndex (1, 1) double = 0;
        samplingRateChannelIndex (1, 1) double = 0;
        integrationTime_s (1, 1) double = 0;
        samplingRate_Hz (1, 1) double = 2E4;
        acquisitionPending (1, 1) logical = false;
        scansPerAcquisition (1, 1) double = 1;
    end

    methods
        function obj = instrument_USB6001(address, numAIChannels, integrationTime_s)
            arguments
                address (1, 1) string = "Dev1";
                numAIChannels (1, 1) double {mustBeInteger, mustBePositive} = 1;
                integrationTime_s (1, 1) double = 0;
            end
            if numAIChannels > 8
                error("instrument_USB6001:InvalidNumAIChannels", ...
                    "numAIChannels must be between 1 and 8.");
            end
            if ~isfinite(integrationTime_s) || integrationTime_s < 0
                error("instrument_USB6001:InvalidIntegrationTime", ...
                    "integrationTime_s must be finite and greater than or equal to 0.");
            end

            obj@instrumentInterface();
            obj.requireSetCheck = false;
            obj.numAIChannels = numAIChannels;
            obj.AI_values = NaN(numAIChannels, 1);
            obj.integrationTime_s = integrationTime_s;
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
                obj.aiVectorChannelIndex = numAIChannels + 1;
            end

            obj.ao0ChannelIndex = numAIChannels + double(numAIChannels > 1) + 1;
            obj.ao1ChannelIndex = obj.ao0ChannelIndex + 1;
            obj.integrationChannelIndex = obj.ao1ChannelIndex + 1;
            obj.samplingRateChannelIndex = obj.integrationChannelIndex + 1;

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
            if ~obj.acquisitionPending && (channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex)
                if obj.integrationTime_s == 0
                    obj.scansPerAcquisition = 5;
                else
                    obj.scansPerAcquisition = max(1, floor(obj.integrationTime_s * obj.samplingRate_Hz));
                end
                obj.communicationHandle.ScansAvailableFcnCount = obj.scansPerAcquisition;
                obj.communicationHandle.ScansAvailableFcn = @(~, ~) [];
                flush(obj.communicationHandle);
                if obj.integrationTime_s == 0
                    start(obj.communicationHandle, "NumScans", obj.scansPerAcquisition);
                else
                    start(obj.communicationHandle, "Duration", obj.integrationTime_s);
                end
                obj.acquisitionPending = true;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case {obj.ao0ChannelIndex, obj.ao1ChannelIndex}
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set AO channels while acquisition is pending. Complete the read or call flush().");
                    end
                    aoIndex = channelIndex - obj.ao0ChannelIndex + 1;
                    obj.AO_values(aoIndex) = setValues(1);
                    write(obj.communicationHandle, obj.AO_values.');
                case obj.integrationChannelIndex
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set integration_time_s while acquisition is pending. Complete the read or call flush().");
                    end
                    value = setValues(1);
                    if ~isfinite(value) || value < 0
                        error("instrument_USB6001:InvalidIntegrationTime", ...
                            "integration_time_s must be finite and greater than or equal to 0.");
                    end
                    obj.integrationTime_s = value;
                case obj.samplingRateChannelIndex
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
            if channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex
                if obj.acquisitionPending
                    if isempty(obj.communicationHandle.ScansAvailableFcn)
                        error("instrument_USB6001:MissingScansAvailableFcn", ...
                            "ScansAvailableFcn must be configured before reading.");
                    end
                    scansRequired = obj.communicationHandle.ScansAvailableFcnCount;
                    scansAvailable = obj.communicationHandle.NumScansAvailable;
                    readDeadline = datetime("now") + seconds(max(obj.integrationTime_s, scansRequired / obj.samplingRate_Hz) + 1);
                    while scansAvailable < scansRequired && datetime("now") < readDeadline
                        pause(1E-3);
                        scansAvailable = obj.communicationHandle.NumScansAvailable;
                    end
                    if scansAvailable < scansRequired
                        error("instrument_USB6001:InsufficientScansAvailable", ...
                            "ScansAvailableFcnCount=%d but NumScansAvailable=%d before read.", ...
                            scansRequired, scansAvailable);
                    end
                    data = read(obj.communicationHandle, scansAvailable, "OutputFormat", "Matrix");
                    obj.acquisitionPending = false;
                    obj.AI_values = mean(data, 1).';
                end

                if channelIndex <= obj.numAIChannels
                    getValues = obj.AI_values(channelIndex);
                else
                    getValues = obj.AI_values;
                end
                return;
            end

            switch channelIndex
                case obj.ao0ChannelIndex
                    getValues = obj.AO_values(1);
                case obj.ao1ChannelIndex
                    getValues = obj.AO_values(2);
                case obj.integrationChannelIndex
                    getValues = obj.integrationTime_s;
                case obj.samplingRateChannelIndex
                    getValues = obj.samplingRate_Hz;
                otherwise
                    error("instrument_USB6001:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
        end
    end
end
