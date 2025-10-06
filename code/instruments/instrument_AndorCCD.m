classdef instrument_AndorCCD < instrumentInterface
    % Andor CCD's that are supported by Andor SDK2 in full vertical binning mode
    % Supports indexed access to the spectrum captured from the CCD.
    % Setting the "pixel_index" channel stores the requested index. Getting
    % "counts" returns the corresponding pixel counts. Repeated
    % requests for the same index trigger a fresh acquisition.

    properties (Constant, Access = private)
        DEFAULT_VSSpeed = int32(0); % default vertical shift speed, 0 = 8.25 uS per shift
        DEFAULT_PREAMP_GAIN = int32(0);
        DEFAULT_EXPOSURE = 10;           % seconds

        READ_MODE_FVB = int32(0);       % Full vertical binning
        READ_MODE_IMAGE = int32(4);     % Full image readout
        ACQ_MODE_SINGLE_SCAN = int32(1);
        DEFAULT_TRIGGER_MODE = int32(0); % Internal trigger
        DRV_SUCCESS = int32(20002);
        TEMP_STATUS_MIN = int32(20034);
        TEMP_STATUS_MAX = int32(20042);
        DRV_IDLE = int32(20073);
        STATUS_POLL_DELAY = 0.05;
    end

    properties (Access = private)
        exposureTime (1, 1) double = instrument_AndorCCD.DEFAULT_EXPOSURE;
        initialized logical = false;
        currentIndex (1, 1) uint32 = 1;
        requestedMask logical = true;
        spectrumData double = [];
        pendingCounts double = NaN;
        currentTemperature double = NaN;
        lastTemperatureStatus int32 = int32(0);
    end

    properties (GetAccess = public, SetAccess = private)
        xpixels (1, 1) uint32 = 0;
        ypixels (1, 1) uint32 = 0;
        pixelCount (1, 1) uint32 = 0;
    end

    methods

        function obj = instrument_AndorCCD(address)
            arguments
                address (1, 1) string = "AndorCCD";
            end

            obj@instrumentInterface();

            if exist("ATMCD64CS.AndorSDK", "class") ~= 8
                try
                    assemblyPath = matlabroot + "\ATMCD64CS.dll";
                    NET.addAssembly(assemblyPath);
                catch assemblyError
                    error("instrument_AndorCCD:AssemblyLoadFailed", ...
                        "Failed to load ATMCD64CS assembly from matlabroot. %s", assemblyError.message);
                end

                if exist("ATMCD64CS.AndorSDK", "class") ~= 8
                    error("instrument_AndorCCD:MissingClass", ...
                        "ATMCD64CS.AndorSDK class not available after loading ATMCD64CS.dll from matlabroot.");
                end
            end

            obj.communicationHandle = ATMCD64CS.AndorSDK();
            handle = obj.communicationHandle;
            obj.checkStatus(handle.Initialize(""), "Initialize");
            obj.initialized = true;

            obj.checkStatus(handle.SetReadMode(obj.READ_MODE_FVB), "SetReadMode");
            obj.checkStatus(handle.SetAcquisitionMode(obj.ACQ_MODE_SINGLE_SCAN), "SetAcquisitionMode");
            obj.checkStatus(handle.SetTriggerMode(obj.DEFAULT_TRIGGER_MODE), "SetTriggerMode");
            obj.checkStatus(handle.SetExposureTime(obj.exposureTime), "SetExposureTime");
            obj.exposureTime = instrument_AndorCCD.DEFAULT_EXPOSURE;
            obj.checkStatus(handle.SetVSSpeed(obj.DEFAULT_VSSpeed), "SetVSSpeed");
            obj.checkStatus(handle.SetPreAmpGain(obj.DEFAULT_PREAMP_GAIN), "SetPreAmpGain");

            xpixels = int32(0);
            ypixels = int32(0);
            [ret, xpixels, ypixels] = handle.GetDetector(xpixels, ypixels);
            obj.checkStatus(ret, "GetDetector");
            obj.xpixels = uint32(xpixels);
            obj.ypixels = uint32(ypixels);
            obj.pixelCount = obj.xpixels;
            assert(obj.pixelCount > 0, "instrument_AndorCCD:NoPixels", "Detector reported zero pixels.");

            obj.requestedMask = true(obj.pixelCount, 1);
            obj.spectrumData = nan(obj.pixelCount, 1);

            handle = obj.communicationHandle;
            obj.checkStatus(handle.SetTemperature(-90), "SetTemperature");
            obj.checkStatus(handle.CoolerON(), "CoolerON");

            obj.address = address;

            obj.addChannel("temperature", setTolerances = 2);
            obj.addChannel("exposure_time");
            obj.addChannel("pixel_index");
            obj.addChannel("counts");

        end

        function delete(obj)
            try
                obj.shutdownCamera();
            catch cameraError
                warning("instrument_AndorCCD:delete", "Failed to shutdown Andor camera cleanly: %s", cameraError.message);
            end
        end

        function flush(~)
            % No buffered commands to flush
        end

        function image = acquireImage(obj)
            % ACQUIREIMAGE captures a full 2D frame from the detector.
            % Returns double precision matrix sized [ypixels, xpixels].

            handle = obj.communicationHandle;

            obj.checkStatus(handle.SetReadMode(obj.READ_MODE_IMAGE), "SetReadModeImage");
            cleanupReadMode = onCleanup(@() obj.checkStatus(handle.SetReadMode(obj.READ_MODE_FVB), "SetReadMode"));

            obj.checkStatus(handle.SetImage(int32(1), int32(1), int32(1), int32(obj.xpixels), int32(1), int32(obj.ypixels)), "SetImage");
            obj.checkStatus(handle.StartAcquisition(), "StartAcquisitionImage");
            obj.checkStatus(handle.WaitForAcquisition(), "WaitForAcquisitionImage");

            totalPixels = double(obj.xpixels) * double(obj.ypixels);
            buffer = NET.createArray("System.Int32", totalPixels);
            ret = handle.GetAcquiredData(buffer, uint32(totalPixels));
            obj.checkStatus(ret, "GetAcquiredDataImage");

            image = reshape(double(buffer), [double(obj.xpixels), double(obj.ypixels)]).';

            obj.invalidateSpectrumCache();
            clear cleanupReadMode; %#ok<CLCLR> ensures read mode reset before returning
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % temperature
                    handle = obj.communicationHandle;
                    temperature = int32(0);
                    [ret, temperature] = handle.GetTemperature(temperature);
                    obj.lastTemperatureStatus = ret;
                    if ret ~= obj.DRV_SUCCESS && ~(ret >= obj.TEMP_STATUS_MIN && ret <= obj.TEMP_STATUS_MAX)
                        obj.checkStatus(ret, "GetTemperature");
                    end
                    obj.currentTemperature = double(temperature);
                case 2 % exposure_time
                    % Exposure is read directly in getReadChannelHelper
                case 3 % pixel_index
                    % Nothing required before returning the current index
                case 4 % counts
                    obj.prepareCounts();
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % temperature
                    getValues = obj.currentTemperature;
                case 2 % exposure_time
                    getValues = obj.exposureTime;
                case 3 % pixel_index
                    getValues = double(obj.currentIndex);
                case 4 % counts
                    getValues = obj.pendingCounts;
                    obj.pendingCounts = NaN;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % temperature
                    targetTemperature = double(setValues(1));
                    assert(isfinite(targetTemperature), "instrument_AndorCCD:InvalidTemperature", ...
                        "Temperature setpoint must be a finite scalar.");
                    handle = obj.communicationHandle;
                    targetTemperatureInt = int32(round(targetTemperature));
                    obj.checkStatus(handle.SetTemperature(targetTemperatureInt), "SetTemperature");
                    obj.currentTemperature = NaN;
                    obj.lastTemperatureStatus = int32(0);
                case 2 % exposure_time
                    newExposure = double(setValues(1));
                    assert(newExposure > 0, "instrument_AndorCCD:InvalidExposure", ...
                        "Exposure time must be positive.");
                    obj.exposureTime = newExposure;
                    handle = obj.communicationHandle;
                    obj.checkStatus(handle.SetExposureTime(obj.exposureTime), "SetExposureTime");
                    obj.invalidateSpectrumCache();
                case 3 % pixel_index
                    idx = double(setValues(1));
                    assert(isfinite(idx) && idx == floor(idx), ...
                        "instrument_AndorCCD:InvalidIndex", ...
                        "Pixel index must be an integer value.");
                    assert(idx >= 1 && idx <= double(obj.pixelCount), ...
                        "instrument_AndorCCD:InvalidIndex", ...
                        "Pixel index must be between 1 and %d.", obj.pixelCount);
                    obj.currentIndex = uint32(idx);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

    end

    methods (Access = private)

        function shutdownCamera(obj)
            if obj.initialized
                try
                    if ~isempty(obj.communicationHandle)
                        obj.communicationHandle.ShutDown();
                    end
                catch shutError
                    warning("instrument_AndorCCD:shutdown", "ShutDown raised an error: %s", shutError.message);
                end
                obj.communicationHandle = [];
                obj.initialized = false;
            end
        end

        function prepareCounts(obj)
            idx = obj.currentIndex;
            if idx < 1 || idx > obj.pixelCount
                error("instrument_AndorCCD:IndexOutOfRange", "Current index %d is outside detector range 1:%d.", idx, obj.pixelCount);
            end

            needsAcquisition = false;
            if isempty(obj.spectrumData) || numel(obj.spectrumData) ~= obj.pixelCount
                needsAcquisition = true;
            elseif obj.requestedMask(idx)
                needsAcquisition = true;
            elseif isnan(obj.spectrumData(idx))
                needsAcquisition = true;
            end

            if needsAcquisition
                obj.acquireSpectrum();
            end

            obj.pendingCounts = obj.spectrumData(idx);
            obj.requestedMask(idx) = true;
        end

        function acquireSpectrum(obj)
            handle = obj.communicationHandle;
            obj.checkStatus(handle.StartAcquisition(), "StartAcquisition");
            obj.checkStatus(handle.WaitForAcquisition(), "WaitForAcquisition");

            buffer = NET.createArray("System.Int32", obj.pixelCount);
            ret = handle.GetAcquiredData(buffer, uint32(obj.pixelCount));
            obj.checkStatus(ret, "GetAcquiredData");

            obj.spectrumData = double(buffer);
            if ~iscolumn(obj.spectrumData)
                obj.spectrumData = reshape(obj.spectrumData, [], 1);
            end
            obj.requestedMask = false(obj.pixelCount, 1);

            try
                handle.FreeInternalMemory();
            catch
                % Some SDK versions don"t require explicit cleanup; ignore failures.
            end
        end

        function checkStatus(obj, statusCode, actionName)
            if statusCode ~= obj.DRV_SUCCESS
                error("instrument_AndorCCD:%sFailed %s failed with status code %d.", actionName, actionName, statusCode);
            end
        end

        function invalidateSpectrumCache(obj)
            if ~isempty(obj.spectrumData)
                obj.spectrumData(:) = NaN;
            end
            if ~isempty(obj.requestedMask)
                obj.requestedMask(:) = true;
            end
            obj.pendingCounts = NaN;
        end

    end

end
