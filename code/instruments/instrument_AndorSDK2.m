classdef instrument_AndorSDK2 < instrumentInterface
    % Thorlabs/Andor CCD with SDK2 in full vertical binning mode
    % Supports indexed access to the spectrum captured from the CCD.
    % Setting the "pixel_index" channel stores the requested index. Getting
    % "counts" returns the corresponding pixel counts. Repeated
    % requests for the same index trigger a fresh acquisition.

    properties (Constant, Access = private)
        DRV_SUCCESS = int32(20002);
        READ_MODE_FVB = int32(4);       % Full vertical binning
        ACQ_MODE_SINGLE_SCAN = int32(1);
        DEFAULT_TRIGGER_MODE = int32(0); % Internal trigger
        DEFAULT_EXPOSURE = 0.1;          % seconds
    end

    properties (Access = private)
        exposureTime (1, 1) double = instrument_AndorSDK2.DEFAULT_EXPOSURE;

        camera = [];
        initialized logical = false;
        currentIndex (1, 1) uint32 = 1;
        requestedMask logical = true;
        spectrumData double = [];
        pendingCounts double = NaN;
    end

    properties (GetAccess = public, SetAccess = private)
        pixelCount (1, 1) uint32 = 0;
    end

    methods

        function obj = instrument_AndorSDK2(address)
            arguments
                address (1, 1) string = "AndorSDK2";
            end

            obj@instrumentInterface();
            obj.address = address;
            obj.requireSetCheck = false;

            obj.exposureTime = instrument_AndorSDK2.DEFAULT_EXPOSURE;

            obj.ensureAssemblyLoaded();
            obj.initializeCamera();
            obj.configureAcquisition();
            obj.determinePixelCount();

            obj.requestedMask = true(obj.pixelCount, 1);
            obj.spectrumData = nan(obj.pixelCount, 1);

            obj.addChannel("pixel_index");
            obj.addChannel("counts");
            obj.addChannel("exposure_time");
        end

        function delete(obj)
            try
                obj.shutdownCamera();
            catch cameraError
                warning("instrument_AndorSDK2:delete", "Failed to shutdown Andor camera cleanly: %s", cameraError.message);
            end
        end

        function flush(~)
            % No buffered commands to flush
        end

    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % pixel_index
                    % Nothing required before returning the current index
                case 2 % counts
                    obj.prepareCounts();
                case 3 % exposure_time
                    % Exposure is read directly in getReadChannelHelper
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % pixel_index
                    getValues = double(obj.currentIndex);
                case 2 % counts
                    getValues = obj.pendingCounts;
                    obj.pendingCounts = NaN;
                case 3 % exposure_time
                    getValues = obj.exposureTime;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % pixel_index
                    idx = double(setValues(1));
                    assert(isfinite(idx) && idx == floor(idx), ...
                        "instrument_AndorSDK2:InvalidIndex", ...
                        "Pixel index must be an integer value.");
                    assert(idx >= 1 && idx <= double(obj.pixelCount), ...
                        "instrument_AndorSDK2:InvalidIndex", ...
                        "Pixel index must be between 1 and %d.", obj.pixelCount);
                    obj.currentIndex = uint32(idx);
                case 3 % exposure_time
                    newExposure = double(setValues(1));
                    assert(newExposure > 0, "instrument_AndorSDK2:InvalidExposure", ...
                        "Exposure time must be positive.");
                    obj.exposureTime = newExposure;
                    obj.checkStatus(obj.camera.SetExposureTime(obj.exposureTime), "SetExposureTime");
                    obj.invalidateSpectrumCache();
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

    end

    methods (Access = private)

        function ensureAssemblyLoaded(~)
            if exist("ATMCD64CS.AndorSDK", "class") == 8
                return;
            end

            try
                assemblyPath = matlabroot + "\ATMCD64CS.dll";
                NET.addAssembly(assemblyPath);
            catch assemblyError
                error("instrument_AndorSDK2:AssemblyLoadFailed", ...
                    "Failed to load ATMCD64CS assembly from matlabroot. %s", assemblyError.message);
            end

            if exist("ATMCD64CS.AndorSDK", "class") ~= 8
                error("instrument_AndorSDK2:MissingClass", ...
                    "ATMCD64CS.AndorSDK class not available after loading ATMCD64CS.dll from matlabroot.");
            end
        end

        function initializeCamera(obj)
            obj.camera = ATMCD64CS.AndorSDK();
            obj.checkStatus(obj.camera.Initialize(""), "Initialize");
            obj.initialized = true;
        end

        function shutdownCamera(obj)
            if obj.initialized
                try
                    if ~isempty(obj.camera)
                        obj.camera.ShutDown();
                    end
                catch shutError
                    warning("instrument_AndorSDK2:shutdown", "ShutDown raised an error: %s", shutError.message);
                end
                obj.camera = [];
                obj.initialized = false;
            end
        end

        function configureAcquisition(obj)
            obj.checkStatus(obj.camera.SetReadMode(obj.READ_MODE_FVB), "SetReadMode");
            obj.checkStatus(obj.camera.SetAcquisitionMode(obj.ACQ_MODE_SINGLE_SCAN), "SetAcquisitionMode");
            obj.checkStatus(obj.camera.SetTriggerMode(obj.DEFAULT_TRIGGER_MODE), "SetTriggerMode");
            obj.checkStatus(obj.camera.SetExposureTime(obj.exposureTime), "SetExposureTime");
        end

        function determinePixelCount(obj)
            xpixels = int32(0);
            ypixels = int32(0);
            [ret, xpixels, ~] = obj.camera.GetDetector(xpixels, ypixels);
            obj.checkStatus(ret, "GetDetector");
            obj.pixelCount = uint32(xpixels);
            assert(obj.pixelCount > 0, "instrument_AndorSDK2:NoPixels", "Detector reported zero pixels.");
        end

        function prepareCounts(obj)
            idx = obj.currentIndex;
            if idx < 1 || idx > obj.pixelCount
                error("instrument_AndorSDK2:IndexOutOfRange", "Current index %d is outside detector range 1:%d.", idx, obj.pixelCount);
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
            obj.checkStatus(obj.camera.StartAcquisition(), "StartAcquisition");
            obj.checkStatus(obj.camera.WaitForAcquisition(), "WaitForAcquisition");

            buffer = NET.createArray('System.Int32', double(obj.pixelCount));
            [ret, buffer] = obj.camera.GetAcquiredData(buffer, int32(obj.pixelCount));
            obj.checkStatus(ret, "GetAcquiredData");

            obj.spectrumData = double(buffer);
            if ~iscolumn(obj.spectrumData)
                obj.spectrumData = reshape(obj.spectrumData, [], 1);
            end
            obj.requestedMask = false(obj.pixelCount, 1);

            try
                obj.camera.FreeInternalMemory();
            catch
                % Some SDK versions don't require explicit cleanup; ignore failures.
            end
        end

        function checkStatus(obj, statusCode, actionName)
            if statusCode ~= obj.DRV_SUCCESS
                error("instrument_AndorSDK2:%sFailed", actionName, ...
                    "%s failed with status code %d.", actionName, statusCode);
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
