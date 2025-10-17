classdef instrument_attodry2100 < instrumentInterface
    % Minimal Attodry2100 integration supporting temperature and field reads
    properties (Access = private)
        libraryDir string
        hasMagnet (1, 1) logical = false
        magnetChannel (1, 1) double = 1
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
            obj.libraryDir = obj.resolveLibraryDir();
            obj.ensureLibraryOnPath();

            obj.communicationHandle = connect(char(address));

            obj.addChannel("T");
            obj.initializeMagnet(options.magnetChannel);
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
                    obj.lastTemperature = obj.readSampleTemperature();
                case 2
                    obj.lastField = obj.readMagneticField();
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
    end

    methods (Access = private)
        function temp = readSampleTemperature(obj)
            [errorNumber, rawTemperature] = sample_getTemperature(obj.communicationHandle);
            obj.assertNoError(errorNumber, "sample_getTemperature");
            temp = double(rawTemperature);
        end

        function field = readMagneticField(obj)
            if ~obj.hasMagnet
                error("instrument_attodry2100:MagnetUnavailable", ...
                    "Magnetic field channel is not available on this system.");
            end
            [errorNumber, rawField] = magnet_getH(obj.communicationHandle, obj.magnetChannel);
            obj.assertNoError(errorNumber, "magnet_getH");
            field = double(rawField);
        end

        function initializeMagnet(obj, requestedChannel)
            requestedChannel = double(requestedChannel);
            try
                [errorNumber, channelCount] = magnet_getNumberOfMagnetChannels(obj.communicationHandle);
            catch ME
                warning("instrument_attodry2100:MagnetProbeFailed", ...
                    "Failed to query magnet channel count: %s", ME.message);
                return;
            end

            if errorNumber ~= 0
                warning("instrument_attodry2100:MagnetUnavailable", ...
                    "magnet_getNumberOfMagnetChannels returned error %d. Magnetic field channel disabled.", errorNumber);
                return;
            end

            channelCount = double(channelCount);
            if channelCount < 1
                return;
            end

            channel = min(channelCount, requestedChannel);
            if channel ~= requestedChannel
                warning("instrument_attodry2100:MagnetChannelAdjusted", ...
                    "Requested magnet channel %d unavailable. Using channel %d instead.", requestedChannel, channel);
            end

            obj.magnetChannel = channel;
            obj.hasMagnet = true;
            obj.addChannel("B");
        end

        function assertNoError(~, errorNumber, operation)
            if errorNumber ~= 0
                error("instrument_attodry2100:CommandFailed", ...
                    "%s returned error %d.", operation, errorNumber);
            end
        end

        function ensureLibraryOnPath(obj)
            libraryPath = char(obj.libraryDir);
            pathEntries = strsplit(path, pathsep);
            if ~any(strcmp(libraryPath, pathEntries))
                addpath(libraryPath);
            end
        end

        function libraryDir = resolveLibraryDir(~)
            instrumentsDir = fileparts(mfilename("fullpath"));
            repoRoot = fileparts(fileparts(instrumentsDir));
            libraryDir = fullfile(repoRoot, "temp", "atto-device-matlab-1.12.0", "atto_device", "CRYO2100");
            if ~isfolder(libraryDir)
                error("instrument_attodry2100:MissingLibrary", ...
                    "Expected CRYO2100 library directory not found at %s.", libraryDir);
            end
        end
    end

end
