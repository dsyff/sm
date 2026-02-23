classdef instrument_USB6001 < instrumentInterface
    properties (Access = private)
        inputDaqs cell = cell(0, 1);
        outputDaqs cell = cell(0, 1);
        AI_values (:, 1) double = NaN(1, 1);
        AO_values (2, 1) double = zeros(2, 1);
        numAIChannels (1, 1) double = 1;
        aiVectorChannelIndex (1, 1) double = 0;
        ao0ChannelIndex (1, 1) double = 0;
        ao1ChannelIndex (1, 1) double = 0;
        aoVectorChannelIndex (1, 1) double = 0;
        integrationChannelIndex (1, 1) double = 0;
        samplingRateChannelIndex (1, 1) double = 0;
        integrationTime_s (1, 1) double = 0;
        samplingRate_Hz (1, 1) double = 2E4;
        acquisitionPending (1, 1) logical = false;
        pendingInputMask (1, :) logical = false;
        aiCacheValidMask (1, :) logical = false;
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
            obj.pendingInputMask = false(1, numAIChannels);
            obj.aiCacheValidMask = false(1, numAIChannels);
            obj.integrationTime_s = integrationTime_s;
            obj.samplingRate_Hz = min(2E4 / numAIChannels, 5E3);

            obj.inputDaqs = cell(numAIChannels, 1);
            for inputIndex = 1:numAIChannels
                inputDaq = daq("ni");
                addinput(inputDaq, address, "ai" + string(inputIndex - 1), "Voltage");
                inputDaq.Rate = obj.samplingRate_Hz;
                inputDaq.ScansAvailableFcn = @(~, ~) [];
                inputDaq.ScansAvailableFcnCount = 1;
                flush(inputDaq);
                obj.inputDaqs{inputIndex} = inputDaq;
            end

            obj.outputDaqs = cell(2, 1);
            for outputIndex = 1:2
                outputDaq = daq("ni");
                addoutput(outputDaq, address, "ao" + string(outputIndex - 1), "Voltage");
                flush(outputDaq);
                obj.outputDaqs{outputIndex} = outputDaq;
            end

            obj.address = address;
            obj.communicationHandle = struct("inputDaqs", {obj.inputDaqs}, "outputDaqs", {obj.outputDaqs});

            for inputIndex = 0:numAIChannels-1
                obj.addChannel("AI" + string(inputIndex));
            end
            nextIndex = numAIChannels;
            if numAIChannels > 1
                aiVectorChannelName = "AI" + join(string(0:numAIChannels-1), "");
                obj.addChannel(aiVectorChannelName, uint64(numAIChannels));
                nextIndex = nextIndex + 1;
                obj.aiVectorChannelIndex = nextIndex;
            end

            obj.ao0ChannelIndex = nextIndex + 1;
            obj.ao1ChannelIndex = obj.ao0ChannelIndex + 1;
            obj.aoVectorChannelIndex = obj.ao1ChannelIndex + 1;
            obj.integrationChannelIndex = obj.aoVectorChannelIndex + 1;
            obj.samplingRateChannelIndex = obj.integrationChannelIndex + 1;

            obj.addChannel("AO0");
            obj.addChannel("AO1");
            obj.addChannel("AO01", 2);
            obj.addChannel("integration_time_s");
            obj.addChannel("sampling_rate_Hz");
        end

        function delete(obj)
            if isempty(obj.inputDaqs) && isempty(obj.outputDaqs)
                return;
            end
            try
                obj.flush();
            catch
            end
        end

        function flush(obj)
            if obj.acquisitionPending
                for inputIndex = 1:numel(obj.inputDaqs)
                    inputDaq = obj.inputDaqs{inputIndex};
                    if isempty(inputDaq)
                        continue;
                    end
                    stop(inputDaq);
                end
                obj.acquisitionPending = false;
            end
            for inputIndex = 1:numel(obj.inputDaqs)
                inputDaq = obj.inputDaqs{inputIndex};
                if isempty(inputDaq)
                    continue;
                end
                flush(inputDaq);
            end
            for outputIndex = 1:numel(obj.outputDaqs)
                outputDaq = obj.outputDaqs{outputIndex};
                if isempty(outputDaq)
                    continue;
                end
                flush(outputDaq);
            end
            obj.AI_values = NaN(obj.numAIChannels, 1);
            obj.pendingInputMask(:) = false;
            obj.aiCacheValidMask(:) = false;
            obj.acquisitionPending = false;
            obj.scansPerAcquisition = 1;
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            if ~(channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex)
                return;
            end
            if obj.integrationTime_s == 0
                return;
            end
            obj.scansPerAcquisition = max(1, floor(obj.integrationTime_s * obj.samplingRate_Hz));
            if channelIndex <= obj.numAIChannels
                inputIndices = channelIndex;
            else
                inputIndices = 1:numel(obj.inputDaqs);
            end
            for inputIndex = inputIndices
                obj.aiCacheValidMask(inputIndex) = false;
                if obj.pendingInputMask(inputIndex)
                    continue;
                end
                inputDaq = obj.inputDaqs{inputIndex};
                inputDaq.ScansAvailableFcnCount = obj.scansPerAcquisition;
                inputDaq.ScansAvailableFcn = @(~, ~) [];
                flush(inputDaq);
                start(inputDaq, "Duration", obj.integrationTime_s);
                obj.pendingInputMask(inputIndex) = true;
            end
            obj.acquisitionPending = any(obj.pendingInputMask);
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
                    write(obj.outputDaqs{aoIndex}, setValues(1));
                case obj.aoVectorChannelIndex
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set AO channels while acquisition is pending. Complete the read or call flush().");
                    end
                    obj.AO_values = setValues;
                    write(obj.outputDaqs{1}, obj.AO_values(1));
                    write(obj.outputDaqs{2}, obj.AO_values(2));
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
                    for inputIndex = 1:numel(obj.inputDaqs)
                        obj.inputDaqs{inputIndex}.Rate = value;
                    end
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex
                if obj.integrationTime_s == 0
                    if channelIndex <= obj.numAIChannels
                        inputIndices = channelIndex;
                    else
                        inputIndices = 1:obj.numAIChannels;
                    end
                    for inputIndex = inputIndices
                        inputDaq = obj.inputDaqs{inputIndex};
                        if isempty(inputDaq.ScansAvailableFcn)
                            error("instrument_USB6001:MissingScansAvailableFcn", ...
                                "ScansAvailableFcn must be configured before reading.");
                        end
                        data = read(inputDaq, 1, "OutputFormat", "Matrix");
                        obj.AI_values(inputIndex) = mean(data, 1).';
                        obj.aiCacheValidMask(inputIndex) = true;
                    end
                else
                    if channelIndex <= obj.numAIChannels
                        inputIndices = channelIndex;
                    else
                        inputIndices = 1:obj.numAIChannels;
                    end
                    for inputIndex = inputIndices
                        if obj.pendingInputMask(inputIndex)
                            inputDaq = obj.inputDaqs{inputIndex};
                            if isempty(inputDaq.ScansAvailableFcn)
                                error("instrument_USB6001:MissingScansAvailableFcn", ...
                                    "ScansAvailableFcn must be configured before reading.");
                            end
                            while logical(inputDaq.Running)
                                pause(1E-3);
                            end
                            scansAvailable = inputDaq.NumScansAvailable;
                            if scansAvailable <= 0
                                error("instrument_USB6001:NoScansAvailable", ...
                                    "No scans are available after acquisition completed.");
                            end
                            data = read(inputDaq, scansAvailable, "OutputFormat", "Matrix");
                            obj.AI_values(inputIndex) = mean(data, 1).';
                            obj.aiCacheValidMask(inputIndex) = true;
                            obj.pendingInputMask(inputIndex) = false;
                            continue;
                        end
                        if ~obj.aiCacheValidMask(inputIndex)
                            error("instrument_USB6001:MissingPendingAcquisition", ...
                                "No pending or cached acquisition for requested AI channel.");
                        end
                    end
                    obj.acquisitionPending = any(obj.pendingInputMask);
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
                case obj.aoVectorChannelIndex
                    getValues = obj.AO_values;
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
