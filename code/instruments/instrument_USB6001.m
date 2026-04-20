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
        accumulationChannelIndex (1, 1) double = 0;
        accumulation (1, 1) double = 1;
        samplingRate_Hz (1, 1) double = 2E4;
        acquisitionPending (1, 1) logical = false;
        pendingInputMask (1, :) logical = false;
        aiCacheValidMask (1, :) logical = false;
    end

    methods
        function obj = instrument_USB6001(address, numAIChannels, accumulation, samplingRate_Hz)
            arguments
                address (1, 1) string = "Dev1";
                numAIChannels (1, 1) double {mustBeInteger, mustBePositive} = 1;
                accumulation (1, 1) double = 1;
                samplingRate_Hz (1, 1) double = 2E4;
            end
            if numAIChannels > 8
                error("instrument_USB6001:InvalidNumAIChannels", ...
                    "numAIChannels must be between 1 and 8.");
            end
            if ~isfinite(accumulation) || accumulation < 1 || mod(accumulation, 1) ~= 0
                error("instrument_USB6001:InvalidAccumulation", ...
                    "accumulation must be a finite integer greater than or equal to 1.");
            end
            if ~isfinite(samplingRate_Hz) || samplingRate_Hz <= 0
                error("instrument_USB6001:InvalidSamplingRate", ...
                    "samplingRate_Hz must be finite and greater than 0.");
            end

            obj@instrumentInterface();
            obj.requireSetCheck = false;
            obj.numAIChannels = numAIChannels;
            obj.AI_values = NaN(numAIChannels, 1);
            obj.pendingInputMask = false(1, numAIChannels);
            obj.aiCacheValidMask = false(1, numAIChannels);
            obj.accumulation = accumulation;
            obj.samplingRate_Hz = samplingRate_Hz;

            obj.inputDaqs = cell(numAIChannels, 1);
            for inputIndex = 1:numAIChannels
                inputDaq = daq("ni");
                addinput(inputDaq, address, "ai" + string(inputIndex - 1), "Voltage");
                inputDaq.Rate = obj.samplingRate_Hz;
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
            obj.accumulationChannelIndex = obj.aoVectorChannelIndex + 1;

            obj.addChannel("AO0");
            obj.addChannel("AO1");
            obj.addChannel("AO01", 2);
            obj.addChannel("accumulations");
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
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            if ~(channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex)
                return;
            end
            if obj.accumulation == 1
                return;
            end
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
                flush(inputDaq);
                start(inputDaq, "NumScans", obj.accumulation);
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
                case obj.accumulationChannelIndex
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set accumulation while acquisition is pending. Complete the read or call flush().");
                    end
                    value = setValues(1);
                    if ~isfinite(value) || value < 1 || mod(value, 1) ~= 0
                        error("instrument_USB6001:InvalidAccumulation", ...
                            "accumulation must be a finite integer greater than or equal to 1.");
                    end
                    obj.accumulation = value;
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex <= obj.numAIChannels || channelIndex == obj.aiVectorChannelIndex
                if channelIndex <= obj.numAIChannels
                    inputIndices = channelIndex;
                else
                    inputIndices = 1:obj.numAIChannels;
                end

                if obj.accumulation == 1
                    for inputIndex = inputIndices
                        data = read(obj.inputDaqs{inputIndex}, 1, "OutputFormat", "Matrix");
                        obj.AI_values(inputIndex) = mean(data, 1).';
                        obj.aiCacheValidMask(inputIndex) = true;
                        obj.pendingInputMask(inputIndex) = false;
                    end
                else
                    for inputIndex = inputIndices
                        if obj.pendingInputMask(inputIndex)
                            inputDaq = obj.inputDaqs{inputIndex};
                            while inputDaq.Running
                                pause(1E-6);
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
                end
                obj.acquisitionPending = any(obj.pendingInputMask);

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
                case obj.accumulationChannelIndex
                    getValues = obj.accumulation;
                otherwise
                    error("instrument_USB6001:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
        end
    end
end
