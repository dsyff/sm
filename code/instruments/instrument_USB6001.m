classdef instrument_USB6001 < instrumentInterface
    properties (Access = private)
        AI_values (8, 1) double = NaN(8, 1);
        AO_values (2, 1) double = zeros(2, 1);
        integrationTime_s (1, 1) double = 0;
        samplingRate_Hz (1, 1) double = 2E4;
        acquisitionPending (1, 1) logical = false;
        scansPerAcquisition (1, 1) double = 1;
    end

    methods
        function obj = instrument_USB6001(address)
            arguments
                address (1, 1) string = "Dev1";
            end

            obj@instrumentInterface();
            obj.requireSetCheck = false;

            handle = daq("ni");
            for inputIndex = 0:7
                addinput(handle, address, "ai" + string(inputIndex), "Voltage");
            end
            for outputIndex = 0:1
                addoutput(handle, address, "ao" + string(outputIndex), "Voltage");
            end
            handle.Rate = obj.samplingRate_Hz;
            flush(handle);

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("AI0");
            obj.addChannel("AI1");
            obj.addChannel("AI2");
            obj.addChannel("AI3");
            obj.addChannel("AI4");
            obj.addChannel("AI5");
            obj.addChannel("AI6");
            obj.addChannel("AI7");
            obj.addChannel("AI01234567", 8);
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
            obj.AI_values = NaN(8, 1);
            obj.scansPerAcquisition = 1;
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            if channelIndex <= 9 && ~obj.acquisitionPending
                obj.scansPerAcquisition = max(1, ceil(obj.integrationTime_s * obj.samplingRate_Hz));
                flush(obj.communicationHandle);
                start(obj.communicationHandle, "continuous");
                obj.acquisitionPending = true;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case {10, 11} % AO0/AO1
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set AO channels while acquisition is pending. Complete the read or call flush().");
                    end
                    aoIndex = channelIndex - 9;
                    obj.AO_values(aoIndex) = setValues(1);
                    write(obj.communicationHandle, obj.AO_values.');
                case 12 % integration_time_s
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
                case 13 % sampling_rate_Hz
                    if obj.acquisitionPending
                        error("instrument_USB6001:SetDuringAcquisition", ...
                            "Cannot set sampling_rate_Hz while acquisition is pending. Complete the read or call flush().");
                    end
                    value = setValues(1);
                    if value <= 0
                        error("instrument_USB6001:InvalidSamplingRate", ...
                            "sampling_rate_Hz must be greater than 0.");
                    end
                    obj.samplingRate_Hz = value;
                    obj.communicationHandle.Rate = value;
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case {1, 2, 3, 4, 5, 6, 7, 8, 9}
                    if obj.acquisitionPending
                        data = read(obj.communicationHandle, obj.scansPerAcquisition, "OutputFormat", "Matrix");
                        stop(obj.communicationHandle);
                        obj.acquisitionPending = false;
                        obj.AI_values = mean(data, 1).';
                    end

                    if channelIndex <= 8
                        getValues = obj.AI_values(channelIndex);
                    else
                        getValues = obj.AI_values;
                    end
                case 10
                    getValues = obj.AO_values(1);
                case 11
                    getValues = obj.AO_values(2);
                case 12
                    getValues = obj.integrationTime_s;
                case 13
                    getValues = obj.samplingRate_Hz;
                otherwise
                    error("instrument_USB6001:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
        end
    end
end
