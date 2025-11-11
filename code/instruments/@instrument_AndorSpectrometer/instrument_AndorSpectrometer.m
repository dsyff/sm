classdef instrument_AndorSpectrometer < instrumentInterface
    % Andor CCD's that are supported by Andor SDK2 in full vertical binning mode
    % Supports indexed access to the spectrum captured from the CCD.
    % Setting the "pixel_index" channel stores the requested index. Getting
    % "counts" returns the corresponding pixel counts. Repeated
    % requests for the same index trigger a fresh acquisition.
    
    properties (Constant, Access = private)
        %vertical and horizontal shift speeds. faster means better fidelity at last pixels to read. slower means lower noise
        DEFAULT_VSSpeed = int32(1); % 0 = 8.25 uS per shift on iDus. larger is slower
        DEFAULT_HSSPEED = int32(0); % 0 = 0.1 MHz for iDus. larger is slower
        %amplifiers. some models only have preamp
        DEFAULT_PREAMP_GAIN = int32(1); % 0 = low gain, 1 = high gain. more gain reduces read noise ratio but saturates earlier
        DEFAULT_OUTAMP_TYPE = int32(0); % 0 for below 750 nm, 1 for above 750 nm
        %more settings
        DEFAULT_AD_CHANNEL = int32(0); % 0 is slower and better for faint signal, 1 is faster but harder to saturate
        DEFAULT_VSAMPLITUDE = int32(0); % 0 is no overvolt. larger is higher voltage, higher noise, and risk of damage. highest speeds may require overvolting
        DEFAULT_EXPOSURE = 0.1; % seconds
        DEFAULT_TRIGGER_MODE = int32(0); % Internal trigger
        DEFAULT_ACCUMULATIONS = uint32(2);
        DEFAULT_FILTER_MODE = int32(2); % Cosmic ray filter on
        STATUS_POLL_DELAY = 0.05; % matlab pause in loop waiting for acquisition
        
        % Andor SDK constants. do not change
        READ_MODE_FVB = int32(0);       % Full vertical binning
        READ_MODE_IMAGE = int32(4);     % Full image readout
        ACQ_MODE_ACCUMULATE = int32(2);

        DRV_SUCCESS = int32(20002);
        TEMP_STATUS_MIN = int32(20034);
        TEMP_STATUS_MAX = int32(20042);
        DRV_IDLE = int32(20073);
        DRV_NOT_AVAILABLE = int32(20992);
        
        PIXELMODE_8_BIT = uint32(1);
        PIXELMODE_14_BIT = uint32(2);
        PIXELMODE_16_BIT = uint32(4);
        PIXELMODE_32_BIT = uint32(8);
        PIXELMODE_COLOR_SHIFT = uint32(16);
        ATSPECTROGRAPH_LIB_ALIAS = "atspectrograph_lib";
    end
    
    properties (Access = private)
        exposureTime (1, 1) double = instrument_AndorSpectrometer.DEFAULT_EXPOSURE;
        accumulations (1, 1) uint32 = instrument_AndorSpectrometer.DEFAULT_ACCUMULATIONS;
        initialized logical = false;
        currentIndex (1, 1) uint32 = 1;
        requestedMask logical = true;
        spectrumData double = [];
        wavelengthData double = [];
        pendingCounts double = NaN;
        pendingWavelength double = NaN;
        currentTemperature double = NaN;
        lastTemperatureStatus int32 = int32(0);
        currentCenterWavelength double = NaN;
        currentGrating int32 = int32(-1);
        spectrographDevice (1, 1) int32 = int32(0);
        spectrographInitialized (1, 1) logical = false;
        spectrographGratingCount (1, 1) int32 = int32(0);
        spectrographGratingIsOneBased (1, 1) logical = true;
    end
    
    properties (GetAccess = public, SetAccess = private)
        xPixels (1, 1) uint32 = 0;
        yPixels (1, 1) uint32 = 0;
        pixelCount (1, 1) uint32 = 0;
        bitDepth (1, 1) uint32 = 0; % bit depth of ADC of chosen channel
        bitsPerPixel (1, 1) uint32 = 0; % bits per pixel in CCD
        preAmpGainMax (1, 1) uint32 = 0;
        vsSpeedMax (1, 1) uint32 = 0;
        hsSpeedMax (1, 1) uint32 = 0;
        vsAmplitudeMax (1, 1) uint32 = 0;
        pixelModeColorValue (1, 1) uint32 = 0;
        pixelSizeX (1, 1) double = NaN;
        pixelSizeY (1, 1) double = NaN;
    end
    
    methods
        
        function obj = instrument_AndorSpectrometer(address)
            arguments
                address (1, 1) string = "AndorSpectrometer";
            end
            
            obj@instrumentInterface();
            
            obj.address = address;
            fprintf("AndorSpectrometer: Loading Andor SDK and initializing CCD...\n");
            try
                obj.initializeCamera();
            catch cameraInitError
                warning("instrument_AndorSpectrometer:CameraInitRetry", ...
                    "CCD initialization failed on first attempt (%s). Retrying once.", cameraInitError.message);
                obj.initializeCamera();
            end
            fprintf("AndorSpectrometer: CCD ready; configuring detector geometry and defaults...\n");
            fprintf("AndorSpectrometer: Enabling CCD cooling to -90 °C...\n");
            try
                fprintf("AndorSpectrometer: CCD configured. Attempting spectrograph initialization...\n");
                obj.initializeSpectrograph();
            catch spectroInitError
                warning("instrument_AndorSpectrometer:SpectrographInitRetry", ...
                    "Spectrograph initialization failed on first attempt (%s). Retrying once.", spectroInitError.message);
                obj.initializeSpectrograph();
            end
            fprintf("AndorSpectrometer: Startup complete—temperature, wavelength, and grating channels ready.\n");
            obj.addChannel("temperature", setTolerances = 2);
            obj.addChannel("exposure_time");
            obj.addChannel("accumulations");
            obj.addChannel("center_wavelength");
            obj.addChannel("grating");
            obj.addChannel("pixel_index");
            obj.addChannel("wavelength");
            obj.addChannel("counts");
            
        end
        
        function delete(obj)
            try
                obj.shutdownCamera();
            catch cameraError
                warning("instrument_AndorSpectrometer:delete", "Failed to shutdown Andor camera cleanly: %s", cameraError.message);
            end
            try
                obj.shutdownSpectrograph();
            catch spectroError
                warning("instrument_AndorSpectrometer:deleteSpectrograph", "Failed to shutdown spectrograph cleanly: %s", spectroError.message);
            end
        end
        
        function flush(~)
            % No buffered commands to flush
        end
        
        function image = acquireImage(obj)
            % ACQUIREIMAGE captures a full 2D frame from the detector.
            % Returns double precision matrix sized [yPixels, xPixels].
            
            handle = obj.communicationHandle;
            
            obj.checkCCDStatus(handle.SetReadMode(obj.READ_MODE_IMAGE), "SetReadModeImage");
            cleanupReadMode = onCleanup(@() obj.checkCCDStatus(handle.SetReadMode(obj.READ_MODE_FVB), "SetReadMode"));
            
            obj.checkCCDStatus(handle.SetImage(int32(1), int32(1), int32(1), int32(obj.xPixels), int32(1), int32(obj.yPixels)), "SetImage");
            obj.checkCCDStatus(handle.StartAcquisition(), "StartAcquisitionImage");
            obj.waitForAcquisitionCompletion(handle, "GetStatusImage");
            
            totalPixels = double(obj.xPixels) * double(obj.yPixels);
            buffer = NET.createArray("System.Int32", totalPixels);
            ret = handle.GetAcquiredData(buffer, uint32(totalPixels));
            obj.checkCCDStatus(ret, "GetAcquiredDataImage");
            
            image = reshape(double(buffer), [double(obj.xPixels), double(obj.yPixels)]).';
            
            obj.checkForSaturation(image, "Image");
            
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
                        obj.checkCCDStatus(ret, "GetTemperature");
                    end
                    obj.currentTemperature = double(temperature);
                case 2 % exposure_time
                    % Exposure is read directly in getReadChannelHelper
                case 3 % accumulations
                    % Accumulations are read directly in getReadChannelHelper
                case 4 % center_wavelength
                    obj.refreshSpectrographCenterWavelength();
                case 5 % grating
                    obj.refreshSpectrographGrating();
                case 6 % pixel_index
                    % Nothing required before returning the current index
                case {7, 8} % wavelength/counts
                    obj.prepareCounts();
            end
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % temperature
                    getValues = obj.currentTemperature;
                case 2 % exposure_time
                    getValues = obj.exposureTime;
                case 3 % accumulations
                    getValues = double(obj.accumulations);
                case 4 % center_wavelength
                    getValues = obj.currentCenterWavelength;
                case 5 % grating
                    getValues = double(obj.currentGrating);
                case 6 % pixel_index
                    getValues = double(obj.currentIndex);
                case 7 % wavelength
                    getValues = obj.pendingWavelength;
                    obj.pendingWavelength = NaN;
                case 8 % counts
                    getValues = obj.pendingCounts;
                    obj.pendingCounts = NaN;
                    obj.pendingWavelength = NaN;
            end
        end
        
        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % temperature
                    targetTemperature = double(setValues(1));
                    assert(isfinite(targetTemperature), "instrument_AndorSpectrometer:InvalidTemperature", ...
                        "Temperature setpoint must be a finite scalar.");
                    handle = obj.communicationHandle;
                    targetTemperatureInt = int32(round(targetTemperature));
                    obj.checkCCDStatus(handle.SetTemperature(targetTemperatureInt), "SetTemperature");
                    obj.currentTemperature = NaN;
                    obj.lastTemperatureStatus = int32(0);
                case 2 % exposure_time
                    newExposure = double(setValues(1));
                    assert(newExposure > 0, "instrument_AndorSpectrometer:InvalidExposure", ...
                        "Exposure time must be positive.");
                    obj.exposureTime = newExposure;
                    handle = obj.communicationHandle;
                    obj.checkCCDStatus(handle.SetExposureTime(obj.exposureTime), "SetExposureTime");
                    obj.invalidateSpectrumCache();
                case 3 % accumulations
                    newAccumulations = double(setValues(1));
                    assert(isfinite(newAccumulations) && newAccumulations == round(newAccumulations) && newAccumulations >= 1, ...
                        "instrument_AndorSpectrometer:InvalidAccumulations", ...
                        "Number of accumulations must be a positive integer.");
                    obj.accumulations = uint32(newAccumulations);
                    handle = obj.communicationHandle;
                    obj.checkCCDStatus(handle.SetNumberAccumulations(int32(obj.accumulations)), "SetNumberAccumulations");
                    obj.invalidateSpectrumCache();
                case 4 % center_wavelength
                    newCenter = double(setValues(1));
                    assert(isfinite(newCenter), ...
                        "instrument_AndorSpectrometer:InvalidCenterWavelength", ...
                        "Center wavelength must be a finite scalar value in nanometers.");
                    if ~obj.spectrographInitialized
                        error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                            "Spectrograph not initialized.");
                    end
                    libAlias = obj.getSpectrographLibAlias();
                    obj.checkSpectrographStatus(calllib(libAlias, 'ATSpectrographSetWavelength', obj.spectrographDevice, single(newCenter)), "ATSpectrographSetWavelength");
                    obj.invalidateSpectrumCache(true);
                    obj.refreshSpectrographCenterWavelength();
                case 5 % grating
                    newGrating = double(setValues(1));
                    assert(isfinite(newGrating) && newGrating == round(newGrating), ...
                        "instrument_AndorSpectrometer:InvalidGrating", ...
                        "Grating index must be an integer value.");
                    candidate = int32(newGrating);
                    if ~obj.spectrographInitialized
                        error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                            "Spectrograph not initialized.");
                    end
                    obj.validateSpectrographGrating(candidate);
                    libAlias = obj.getSpectrographLibAlias();
                    obj.checkSpectrographStatus(calllib(libAlias, 'ATSpectrographSetGrating', obj.spectrographDevice, candidate), "ATSpectrographSetGrating");
                    obj.invalidateSpectrumCache(true);
                    obj.refreshSpectrographGrating();
                    obj.refreshSpectrographCenterWavelength();
                case 6 % pixel_index
                    idx = double(setValues(1));
                    assert(isfinite(idx) && idx == round(idx), ...
                        "instrument_AndorSpectrometer:InvalidIndex", ...
                        "Pixel index must be an integer value.");
                    assert(idx >= 1 && idx <= double(obj.pixelCount), ...
                        "instrument_AndorSpectrometer:InvalidIndex", ...
                        "Pixel index must be between 1 and %d.", obj.pixelCount);
                    obj.currentIndex = uint32(idx);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end
        
    end
    
    methods (Access = private)
        function initializeCamera(obj)
            if exist("ATMCD64CS.AndorSDK", "class") ~= 8
                try
                    assemblyPath = matlabroot + "\ATMCD64CS.dll";
                    NET.addAssembly(assemblyPath);
                catch assemblyError
                    error("instrument_AndorSpectrometer:AssemblyLoadFailed", ...
                        "Failed to load ATMCD64CS assembly from matlabroot. %s", assemblyError.message);
                end

                if exist("ATMCD64CS.AndorSDK", "class") ~= 8
                    error("instrument_AndorSpectrometer:MissingClass", ...
                        "ATMCD64CS.AndorSDK class not available after loading ATMCD64CS.dll from matlabroot.");
                end
            end

            obj.communicationHandle = ATMCD64CS.AndorSDK();
            handle = obj.communicationHandle;
            obj.checkCCDStatus(handle.Initialize(""), "Initialize");
            obj.initialized = true;

            obj.checkCCDStatus(handle.SetReadMode(obj.READ_MODE_FVB), "SetReadMode");
            obj.checkCCDStatus(handle.SetAcquisitionMode(obj.ACQ_MODE_ACCUMULATE), "SetAcquisitionMode");
            obj.checkCCDStatus(handle.SetTriggerMode(obj.DEFAULT_TRIGGER_MODE), "SetTriggerMode");
            obj.checkCCDStatus(handle.SetExposureTime(obj.exposureTime), "SetExposureTime");
            obj.exposureTime = instrument_AndorSpectrometer.DEFAULT_EXPOSURE;
            obj.checkCCDStatus(handle.SetNumberAccumulations(int32(obj.accumulations)), "SetNumberAccumulations");
            obj.accumulations = instrument_AndorSpectrometer.DEFAULT_ACCUMULATIONS;
            obj.checkCCDStatus(handle.SetVSSpeed(obj.DEFAULT_VSSpeed), "SetVSSpeed");
            obj.checkCCDStatus(handle.SetADChannel(obj.DEFAULT_AD_CHANNEL), "SetADChannel");
            obj.checkCCDStatus(handle.SetVSAmplitude(obj.DEFAULT_VSAMPLITUDE), "SetVSAmplitude");
            obj.checkCCDStatus(handle.SetHSSpeed(obj.DEFAULT_OUTAMP_TYPE, obj.DEFAULT_HSSPEED), "SetHSSpeed");
            obj.checkCCDStatus(handle.SetPreAmpGain(obj.DEFAULT_PREAMP_GAIN), "SetPreAmpGain");
            obj.checkCCDStatus(handle.SetFilterMode(obj.DEFAULT_FILTER_MODE), "SetFilterMode");

            detectorX = int32(0);
            detectorY = int32(0);
            [ret, detectorX, detectorY] = handle.GetDetector(detectorX, detectorY);
            obj.checkCCDStatus(ret, "GetDetector");
            obj.xPixels = uint32(detectorX);
            obj.yPixels = uint32(detectorY);
            obj.pixelCount = obj.xPixels;
            assert(obj.pixelCount > 0, "instrument_AndorSpectrometer:NoPixels", ...
                "Detector reported zero pixels.");

            preAmpGainCount = int32(0);
            [ret, preAmpGainCount] = handle.GetNumberPreAmpGains(preAmpGainCount);
            obj.checkCCDStatus(ret, "GetNumberPreAmpGains");
            obj.preAmpGainMax = uint32(preAmpGainCount - 1);

            vsSpeedCount = int32(0);
            [ret, vsSpeedCount] = handle.GetNumberVSSpeeds(vsSpeedCount);
            obj.checkCCDStatus(ret, "GetNumberVSSpeeds");
            obj.vsSpeedMax = uint32(vsSpeedCount - 1);

            hsSpeedCount = int32(0);
            [ret, hsSpeedCount] = handle.GetNumberHSSpeeds(obj.DEFAULT_AD_CHANNEL, obj.DEFAULT_OUTAMP_TYPE, hsSpeedCount);
            obj.checkCCDStatus(ret, "GetNumberHSSpeeds");
            obj.hsSpeedMax = uint32(hsSpeedCount - 1);

            vsAmplitudeCount = int32(0);
            [ret, vsAmplitudeCount] = handle.GetNumberVSAmplitudes(vsAmplitudeCount);
            obj.checkCCDStatus(ret, "GetNumberVSAmplitudes");
            obj.vsAmplitudeMax = uint32(vsAmplitudeCount - 1);

            bitDepthValue = int32(0);
            [ret, bitDepthValue] = handle.GetBitDepth(obj.DEFAULT_AD_CHANNEL, bitDepthValue);
            obj.checkCCDStatus(ret, "GetBitDepth");
            obj.bitDepth = uint32(bitDepthValue);

            capabilitiesType = handle.GetType().Assembly.GetType("ATMCD64CS.AndorSDK+AndorCapabilities");
            if isempty(capabilitiesType)
                error("instrument_AndorSpectrometer:MissingCapabilitiesType", ...
                    "ATMCD64CS.AndorSDK+AndorCapabilities type not found in loaded assembly.");
            end
            capabilities = System.Activator.CreateInstance(capabilitiesType);
            capabilities.ulSize = uint32(System.Runtime.InteropServices.Marshal.SizeOf(capabilities));
            ret = handle.GetCapabilities(capabilities);
            obj.checkCCDStatus(ret, "GetCapabilities");
            pixelModeBits = uint32(capabilities.ulPixelMode);
            obj.bitsPerPixel = obj.deriveBitsPerPixel(pixelModeBits);
            obj.pixelModeColorValue = bitshift(pixelModeBits, -double(obj.PIXELMODE_COLOR_SHIFT));
            if obj.pixelModeColorValue ~= 0
                fprintf("instrument_AndorSpectrometer: Camera reports non-monochrome pixel mode value %u. Spectrum reads assume grayscale ordering.\n", obj.pixelModeColorValue);
            end

            xSize = single(0);
            ySize = single(0);
            [ret, xSize, ySize] = handle.GetPixelSize(xSize, ySize);
            obj.checkCCDStatus(ret, "GetPixelSize");
            obj.pixelSizeX = double(xSize);
            obj.pixelSizeY = double(ySize);

            obj.requestedMask = true(obj.pixelCount, 1);
            obj.spectrumData = nan(obj.pixelCount, 1);
            obj.wavelengthData = [];
            obj.pendingCounts = NaN;
            obj.pendingWavelength = NaN;

            obj.checkCCDStatus(handle.SetTemperature(-90), "SetTemperature");
            obj.checkCCDStatus(handle.CoolerON(), "CoolerON");

        end

        function initializeSpectrograph(obj)
            libAlias = obj.getSpectrographLibAlias();
            headerPath = obj.getSpectrographHeaderPath();
            dllPath = obj.getSpectrographDllPath();
            if ~isfile(dllPath)
                error("instrument_AndorSpectrometer:MissingSpectrographDll", ...
                    "ATSpectrograph DLL was not found at %s.", dllPath);
            end

            fprintf("AndorSpectrometer: Loading ATSpectrograph DLL and probing devices...\n");
            if ~libisloaded(libAlias)
                [notfoundSymbols, loadWarnings] = loadlibrary(dllPath, headerPath, 'alias', char(libAlias));
                if ~isempty(loadWarnings)
                    for warnIdx = 1:numel(loadWarnings)
                        warning("instrument_AndorSpectrometer:SpectrographLoadWarning", ...
                            "loadlibrary warning %d/%d: %s", warnIdx, numel(loadWarnings), loadWarnings{warnIdx});
                    end
                end
                if ~isempty(notfoundSymbols)
                    warning("instrument_AndorSpectrometer:SpectrographLoadMissing", ...
                        "loadlibrary reported unresolved symbols: %s", strjoin(cellstr(notfoundSymbols), ", "));
                end
            end

            status = calllib(libAlias, 'ATSpectrographInitialize', '');
            obj.checkSpectrographStatus(status, "ATSpectrographInitialize");

            [status, deviceCount] = calllib(libAlias, 'ATSpectrographGetNumberDevices', int32(0));
            obj.checkSpectrographStatus(status, "ATSpectrographGetNumberDevices");
            deviceCount = double(deviceCount);
            if deviceCount <= 0
                error("instrument_AndorSpectrometer:SpectrographUnavailable", ...
                    "No ATSpectrograph devices detected by the SDK.");
            end

            fprintf("AndorSpectrometer: Spectrograph online; reading grating and wavelength settings...\n");
            obj.spectrographDevice = int32(0);
            obj.spectrographInitialized = true;

            try
                obj.executeSpectrographProbe();
            catch firstProbeError
                firstReport = getReport(firstProbeError, 'extended', 'hyperlinks', 'off');
                warning("instrument_AndorSpectrometer:SpectrographInitRetry", ...
                    "Spectrograph probe failed on first attempt. First error:\n%s\nRetrying once...", firstReport);

                obj.spectrographInitialized = false;
                status = calllib(libAlias, 'ATSpectrographInitialize', '');
                obj.checkSpectrographStatus(status, "ATSpectrographInitialize-Retry");

                [status, deviceCount] = calllib(libAlias, 'ATSpectrographGetNumberDevices', int32(0));
                obj.checkSpectrographStatus(status, "ATSpectrographGetNumberDevices-Retry");
                deviceCount = double(deviceCount);
                if deviceCount <= 0
                    error("instrument_AndorSpectrometer:SpectrographUnavailable", ...
                        "No ATSpectrograph devices detected by the SDK after retry.");
                end

                obj.spectrographDevice = int32(0);
                obj.spectrographInitialized = true;

                try
                    obj.executeSpectrographProbe();
                catch secondProbeError
                    secondReport = getReport(secondProbeError, 'extended', 'hyperlinks', 'off');
                    error("instrument_AndorSpectrometer:SpectrographProbeFailed", ...
                        "Spectrograph initialization failed after retry.\nFirst error:\n%s\nSecond error:\n%s", ...
                        firstReport, secondReport);
                end
            end
        end
        
        function shutdownCamera(obj)
            if obj.initialized
                try
                    if ~isempty(obj.communicationHandle)
                        obj.communicationHandle.ShutDown();
                    end
                catch shutError
                    warning("instrument_AndorSpectrometer:shutdown", "ShutDown raised an error: %s", shutError.message);
                end
                obj.communicationHandle = [];
                obj.initialized = false;
            end
        end
        
        function wavelength = querySpectrographWavelength(obj)
            if ~obj.spectrographInitialized
                error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                    "Spectrograph not initialized.");
            end
            libAlias = obj.getSpectrographLibAlias();

            [ret, spectroPixelCount] = calllib(libAlias, 'ATSpectrographGetNumberPixels', obj.spectrographDevice, int32(0));
            obj.checkSpectrographStatus(ret, "ATSpectrographGetNumberPixels");
            spectroPixelCount = double(spectroPixelCount);
            if spectroPixelCount <= 0
                error("instrument_AndorSpectrometer:WavelengthQueryFailed", ...
                    "Spectrograph reported an invalid pixel count (%d).", spectroPixelCount);
            end

            requestedPixelCount = int32(min(double(obj.pixelCount), spectroPixelCount));
            calibrationBuffer = zeros(double(requestedPixelCount), 1, 'single');
            [ret, calibrationBuffer] = calllib(libAlias, 'ATSpectrographGetCalibration', obj.spectrographDevice, calibrationBuffer, requestedPixelCount);
            obj.checkSpectrographStatus(ret, "ATSpectrographGetCalibration");
            wavelength = double(calibrationBuffer(:));

            detectorPixelCount = double(obj.pixelCount);
            if detectorPixelCount > numel(wavelength)
                wavelength = [wavelength; nan(detectorPixelCount - numel(wavelength), 1)];
            elseif detectorPixelCount < numel(wavelength)
                wavelength = wavelength(1:detectorPixelCount);
            end

            if numel(wavelength) ~= detectorPixelCount
                error("instrument_AndorSpectrometer:WavelengthSizeMismatch", ...
                    "Expected %d wavelength samples but received %d.", detectorPixelCount, numel(wavelength));
            end
        end

        function shutdownSpectrograph(obj)
            if ~obj.spectrographInitialized
                return;
            end
            libAlias = obj.getSpectrographLibAlias();
            if libisloaded(libAlias)
                try
                    status = calllib(libAlias, 'ATSpectrographClose');
                    statusStr = obj.toSpectrographStatusString(status);
                    if ~strcmp(statusStr, "ATSPECTROGRAPH_SUCCESS")
                        warning("instrument_AndorSpectrometer:SpectrographClose", ...
                            "ATSpectrographClose returned status %s.", statusStr);
                    end
                catch closeError
                    warning("instrument_AndorSpectrometer:SpectrographClose", ...
                        "ATSpectrographClose raised an error: %s", closeError.message);
                end
            end
            obj.spectrographInitialized = false;
            obj.currentCenterWavelength = NaN;
            obj.currentGrating = int32(-1);
            obj.spectrographGratingCount = int32(0);
            obj.spectrographGratingIsOneBased = true;
        end

        function libAlias = getSpectrographLibAlias(obj)
            libAlias = obj.ATSPECTROGRAPH_LIB_ALIAS;
        end

        function headerPath = getSpectrographHeaderPath(~)
            classFile = which('instrument_AndorSpectrometer');
            if isempty(classFile)
                error("instrument_AndorSpectrometer:HeaderLookupFailed", ...
                    "Unable to locate instrument_AndorSpectrometer class file for header lookup.");
            end
            headerPath = fullfile(fileparts(classFile), 'atspectrograph.h');
            if ~isfile(headerPath)
                error("instrument_AndorSpectrometer:MissingSpectrographHeader", ...
                    "atspectrograph.h was not found at %s.", headerPath);
            end
        end

        function dllPath = getSpectrographDllPath(~)
            dllPath = fullfile(matlabroot, "ATSpectrograph", "x64", "atspectrograph.dll");
        end

        function checkSpectrographStatus(obj, statusCode, actionName)
            if nargin < 3
                actionName = "";
            end
            actionName = string(actionName);
            statusStr = obj.toSpectrographStatusString(statusCode);
            if strcmp(statusStr, "ATSPECTROGRAPH_SUCCESS")
                return;
            end

            error("instrument_AndorSpectrometer:SpectrographError", ...
                "%s failed with status %s.", actionName, statusStr);
        end
        
        function statusStr = toSpectrographStatusString(~, statusValue)
            if ischar(statusValue)
                cleaned = statusValue(statusValue ~= 0);
                statusStr = strtrim(cleaned);
            elseif isstring(statusValue)
                statusStr = strtrim(statusValue);
            else
                statusStr = string(statusValue);
            end
            if strlength(statusStr) == 0
                error("instrument_AndorSpectrometer:SpectrographStatusParse", ...
                    "Spectrograph returned an unexpected status value of type %s.", class(statusValue));
            end
            statusStr = char(statusStr);
        end

        function pushSpectrographPixelGeometry(obj)
            if ~obj.spectrographInitialized
                error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                    "Spectrograph not initialized.");
            end
            if obj.pixelCount == 0 || ~isfinite(obj.pixelSizeX) || obj.pixelSizeX <= 0
                return;
            end
            libAlias = obj.getSpectrographLibAlias();
            obj.checkSpectrographStatus(calllib(libAlias, 'ATSpectrographSetPixelWidth', obj.spectrographDevice, single(obj.pixelSizeX)), "ATSpectrographSetPixelWidth");
            obj.checkSpectrographStatus(calllib(libAlias, 'ATSpectrographSetNumberPixels', obj.spectrographDevice, int32(obj.pixelCount)), "ATSpectrographSetNumberPixels");
        end

        function refreshSpectrographCenterWavelength(obj)
            if ~obj.spectrographInitialized
                error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                    "Spectrograph not initialized.");
            end
            libAlias = obj.getSpectrographLibAlias();
            [ret, wavelengthValue] = calllib(libAlias, 'ATSpectrographGetWavelength', obj.spectrographDevice, single(0));
            obj.checkSpectrographStatus(ret, "ATSpectrographGetWavelength");
            obj.currentCenterWavelength = double(wavelengthValue);
        end

        function refreshSpectrographGrating(obj)
            if ~obj.spectrographInitialized
                error("instrument_AndorSpectrometer:SpectrographNotInitialized", ...
                    "Spectrograph not initialized.");
            end
            libAlias = obj.getSpectrographLibAlias();
            [ret, gratingCount] = calllib(libAlias, 'ATSpectrographGetNumberGratings', obj.spectrographDevice, int32(0));
            obj.checkSpectrographStatus(ret, "ATSpectrographGetNumberGratings");
            obj.spectrographGratingCount = int32(gratingCount);

            [ret, currentGrating] = calllib(libAlias, 'ATSpectrographGetGrating', obj.spectrographDevice, int32(0));
            obj.checkSpectrographStatus(ret, "ATSpectrographGetGrating");
            current = int32(currentGrating);
            obj.currentGrating = current;

            if obj.spectrographGratingCount > 0
                if current >= 1 && current <= obj.spectrographGratingCount
                    obj.spectrographGratingIsOneBased = true;
                elseif current >= 0 && current < obj.spectrographGratingCount
                    obj.spectrographGratingIsOneBased = false;
                end
            end
        end

        function executeSpectrographProbe(obj)
            obj.pushSpectrographPixelGeometry();
            obj.refreshSpectrographGrating();
            obj.refreshSpectrographCenterWavelength();
        end

        function validateSpectrographGrating(obj, candidate)
            obj.refreshSpectrographGrating();
            if obj.spectrographGratingCount <= 0
                error("instrument_AndorSpectrometer:NoGratings", ...
                    "Spectrograph reports zero available gratings.");
            end

            if obj.spectrographGratingIsOneBased
                minIndex = 1;
                maxIndex = double(obj.spectrographGratingCount);
            else
                minIndex = 0;
                maxIndex = double(obj.spectrographGratingCount) - 1;
            end

            candidateValue = double(candidate);
            if candidateValue < minIndex || candidateValue > maxIndex
                error("instrument_AndorSpectrometer:InvalidGrating", ...
                    "Grating index must be between %d and %d.", int32(minIndex), int32(maxIndex));
            end
        end

        function prepareCounts(obj)
            if ~isnan(obj.pendingCounts) && ~isnan(obj.pendingWavelength)
                return;
            end
            idx = obj.currentIndex;
            if idx < 1 || idx > obj.pixelCount
                error("instrument_AndorSpectrometer:IndexOutOfRange", "Current index %d is outside detector range 1:%d.", idx, obj.pixelCount);
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
            if isempty(obj.wavelengthData) || numel(obj.wavelengthData) ~= double(obj.pixelCount)
                obj.wavelengthData = obj.querySpectrographWavelength();
                if ~isempty(obj.wavelengthData) && ~iscolumn(obj.wavelengthData)
                    obj.wavelengthData = reshape(obj.wavelengthData, [], 1);
                end
            end
            obj.pendingWavelength = obj.wavelengthData(idx);
            obj.requestedMask(idx) = true;
        end
        
        function acquireSpectrum(obj)
            handle = obj.communicationHandle;
            obj.checkCCDStatus(handle.StartAcquisition(), "StartAcquisition");
            obj.waitForAcquisitionCompletion(handle, "GetStatus");
            
            buffer = NET.createArray("System.Int32", obj.pixelCount);
            ret = handle.GetAcquiredData(buffer, uint32(obj.pixelCount));
            obj.checkCCDStatus(ret, "GetAcquiredData");
            
            obj.spectrumData = double(buffer);
            if ~iscolumn(obj.spectrumData)
                obj.spectrumData = reshape(obj.spectrumData, [], 1);
            end
            obj.wavelengthData = obj.querySpectrographWavelength();
            if ~isempty(obj.wavelengthData) && ~iscolumn(obj.wavelengthData)
                obj.wavelengthData = reshape(obj.wavelengthData, [], 1);
            end
            obj.requestedMask = false(obj.pixelCount, 1);
            
            obj.checkForSaturation(obj.spectrumData, "Spectrum");
            
            try
                handle.FreeInternalMemory();
            catch
                % Some SDK versions don"t require explicit cleanup; ignore failures.
            end
        end

        function waitForAcquisitionCompletion(obj, handle, actionLabel)
            if nargin < 3 || isempty(actionLabel)
                actionLabel = "GetStatus";
            end

            totalDelay = obj.exposureTime * double(obj.accumulations);
            if totalDelay > 0
                pause(totalDelay);
            end

            while true
                statusCode = int32(0);
                [ret, statusCode] = handle.GetStatus(statusCode);
                obj.checkCCDStatus(ret, char(actionLabel));
                if statusCode == obj.DRV_IDLE
                    break;
                end
                pause(obj.STATUS_POLL_DELAY);
            end
        end
        
        function checkCCDStatus(obj, statusCode, actionName)
            if nargin < 3
                actionName = "";
            end
            actionName = string(actionName);
            if statusCode == obj.DRV_SUCCESS
                return;
            end
            
            if statusCode == obj.DRV_NOT_AVAILABLE
                if actionName == "Initialize"
                    error("instrument_AndorSpectrometer:CCDError", ...
                        "CCD Error: Initialize failed with DRV_NOT_AVAILABLE (20992). Close SOLIS before using this driver in MATLAB.");
                end
                fprintf("instrument_AndorSpectrometer: CCD Warning: %s returned DRV_NOT_AVAILABLE (20992). This feature is not supported by the current camera configuration.\n", char(actionName));
                return;
            end
            
            error("instrument_AndorSpectrometer:CCDError", ...
                "CCD Error: %s failed with status code %d.", actionName, statusCode);
        end
        
        function invalidateSpectrumCache(obj, clearWavelength)
            if nargin < 2
                clearWavelength = false;
            end
            if ~isempty(obj.spectrumData)
                obj.spectrumData(:) = NaN;
            end
            if clearWavelength
                obj.wavelengthData = [];
            end
            if ~isempty(obj.requestedMask)
                obj.requestedMask(:) = true;
            end
            obj.pendingCounts = NaN;
            obj.pendingWavelength = NaN;
        end
        
        function bits = deriveBitsPerPixel(obj, pixelModeBits)
            bits = obj.bitDepth;
            
            if nargin >= 2 && ~isempty(pixelModeBits)
                pixelModeBits = uint32(pixelModeBits);
                masks = [
                    obj.PIXELMODE_32_BIT,
                    obj.PIXELMODE_16_BIT,
                    obj.PIXELMODE_14_BIT,
                    obj.PIXELMODE_8_BIT
                    ];
                values = uint32([32, 16, 14, 8]);
                
                for k = 1:numel(masks)
                    if bitand(pixelModeBits, masks(k)) ~= 0
                        bits = values(k);
                        return;
                    end
                end
            end
        end
        
        function checkForSaturation(obj, data, context)
            if obj.bitDepth == 0
                return;
            end
            
            accumulationCount = max(double(obj.accumulations), 1);

            dataPerAccumulation = data ./ accumulationCount;
            saturationLevel = double(2.^double(obj.bitDepth) - 1);
            if any(dataPerAccumulation(:) >= saturationLevel)
                fprintf("instrument_AndorSpectrometer: %s acquisition reached the ADC limit (>= %.0f). Consider reducing exposure or gain.\n", ...
                    context, saturationLevel);
            end
        end
    end
end
