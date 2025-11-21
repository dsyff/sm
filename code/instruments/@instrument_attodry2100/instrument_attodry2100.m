classdef instrument_attodry2100 < instrumentInterface
    % Minimal Attodry2100 integration supporting temperature and field reads
    properties (Access = private)
        hasMagnet (1, 1) logical = false
        magnetChannel (1, 1) double = 0
        lastTemperature double = NaN
        lastField double = NaN
    end

    methods
        function obj = instrument_attodry2100(address, options)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                options.magnetChannel (1, 1) double {mustBeInteger, mustBePositive} = 1
            end
            obj@instrumentInterface();

            obj.address = address;

            obj.communicationHandle = connect(char(address));
            obj.initializeMagnet(options.magnetChannel);

            obj.addChannel("T", setTolerances = 0.1);
            obj.addChannel("B", setTolerances = 1E-2);
        end

        function delete(obj)
            if ~isempty(obj.communicationHandle)
                tcp = obj.communicationHandle; %#ok<NASGU>
                obj.communicationHandle = [];
                % ensure tcpclient connection closes cleanly
                clear tcp;
            end
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    [errorNumber, rawTemperature] = sample_getTemperature(obj.communicationHandle);
                    obj.assertNoError(errorNumber, "sample_getTemperature");
                    obj.lastTemperature = double(rawTemperature);
                case 2
                    if ~obj.hasMagnet
                        error("instrument_attodry2100:MagnetUnavailable", ...
                            "Magnetic field channel is not available on this system.");
                    end
                    [errorNumber, rawField] = magnet_getH(obj.communicationHandle, obj.magnetChannel);
                    obj.assertNoError(errorNumber, "magnet_getH");
                    obj.lastField = double(rawField);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    getValues = obj.lastTemperature;
                case 2
                    getValues = obj.lastField;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    errorNumber = sample_setSetPoint(handle, setValues);
                    obj.assertNoError(errorNumber, "sample_setSetPoint");
                    if setValues > 1.5
                        errorNumber = sample_startTempControl(handle);
                        obj.assertNoError(errorNumber, "sample_startTempControl");
                    else
                        errorNumber = sample_stopTempControl(handle);
                        obj.assertNoError(errorNumber, "sample_stopTempControl");
                    end
                case 2
                    errorNumber = magnet_setHSetPoint(handle, obj.magnetChannel, setValues);
                    obj.assertNoError(errorNumber, "magnet_setHSetPoint");
                    errorNumber = magnet_startFieldControl(handle, obj.magnetChannel);
                    obj.assertNoError(errorNumber, "magnet_startFieldControl");
                    
            end
        end
    end

    methods (Access = private)
        function initializeMagnet(obj, requestedChannel)
            requestedChannel = double(requestedChannel);
            try
                [errorNumber, channelCount] = magnet_getNumberOfMagnetChannels(obj.communicationHandle);
            catch ME
                error("instrument_attodry2100:MagnetProbeFailed", ...
                    "Failed to query magnet channel count: %s", ME.message);
            end

            obj.assertNoError(errorNumber, "magnet_getNumberOfMagnetChannels");

            channelCount = double(channelCount);
            if channelCount < 1
                error("instrument_attodry2100:MagnetUnavailable", ...
                    "Cryostat reports zero magnet channels.");
            end

            channel = min(channelCount - 1, requestedChannel);
            obj.magnetChannel = channel;
            obj.hasMagnet = true;
        end

        function assertNoError(obj, errorNumber, operation)
            if errorNumber ~= 0
                errStr  = system_errorNumberToString(obj.communicationHandle, errorNumber);

                error("instrument_attodry2100:CommandFailed", ...
                    "%s returned error %d: %s", ...
                    operation, errorNumber, string(errStr));
            end
        end
    end

end
