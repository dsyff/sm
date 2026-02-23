classdef instrument_CS165MU < instrumentInterface
    % instrument_CS165MU
    % Thorlabs CS165MU (TLCamera .NET SDK) integration.
    %
    % - Always opens the first discovered camera; errors if none are found.
    % - Provides a live-view figure (square pixels) updated with drawnow limitrate.
    % - Exposes camera settings as numeric instrument channels.
    %
    % Notes:
    % - This driver uses .NET assemblies located in @instrument_CS165MU/dlls.
    % - Uses which(class(obj)) to locate dll folder and adds it to PATH.

    properties (Access = private)
        tlCameraSDK;
        serialNumbers;
        tlCamera;

        liveFigure;
        liveAxes;
        liveImage;

        liveTimer;
        liveEnabled (1, 1) logical = false;

        pendingValue double = NaN;
    end

    properties (GetAccess = public, SetAccess = private)
        sensorWidth_px (1, 1) double = NaN;
        sensorHeight_px (1, 1) double = NaN;
    end

    methods
        function obj = instrument_CS165MU(address)
            arguments
                address (1, 1) string = "";
            end

            obj@instrumentInterface();

            obj.loadDotNetAssembliesAndPath();
            obj.openCameraOrError(address);
            obj.ensureLiveFigure();

            % --- Channels (numeric only)
            % Acquisition control
            obj.requireSetCheck = false;

            obj.addChannel("continuous");

            % Exposure
            obj.addChannel("exposure_ms");

            % ROI (pixel units), exposed as scalar channels
            obj.addChannel("roi_origin_x_px");
            obj.addChannel("roi_origin_y_px");
            obj.addChannel("roi_width_px");
            obj.addChannel("roi_height_px");

            % Binning, exposed as a single scalar channel (always use binX = binY)
            obj.addChannel("bin");

            % Read-only status helpers
            obj.addChannel("queued_frames");
        end

        function delete(obj)
            obj.stopContinuousAcquisition();

            if ~isempty(obj.liveTimer)
                try
                    stop(obj.liveTimer);
                catch
                end
                try
                    delete(obj.liveTimer);
                catch
                end
                obj.liveTimer = [];
            end

            if ~isempty(obj.liveFigure) && isvalid(obj.liveFigure)
                try
                    delete(obj.liveFigure);
                catch
                end
            end

            % Close camera
            if ~isempty(obj.tlCamera)
                try
                    if obj.tlCamera.IsArmed
                        obj.tlCamera.Disarm;
                    end
                catch
                end
                try
                    obj.tlCamera.Dispose;
                catch
                end
                try
                    delete(obj.tlCamera);
                catch
                end
                obj.tlCamera = [];
            end

            if ~isempty(obj.serialNumbers)
                try
                    delete(obj.serialNumbers);
                catch
                end
                obj.serialNumbers = [];
            end

            if ~isempty(obj.tlCameraSDK)
                try
                    obj.tlCameraSDK.Dispose;
                catch
                end
                try
                    delete(obj.tlCameraSDK);
                catch
                end
                obj.tlCameraSDK = [];
            end
        end

        function image2D = acquireSingleImage(obj)
            % acquireSingleImage
            % Returns a single acquired frame as a 2D uint16 array (Height x Width).
            %
            % If continuous acquisition is enabled, this will attempt to pull a pending
            % frame; if none is pending it will issue a software trigger and wait.

            if isempty(obj.tlCamera)
                error("instrument_CS165MU:NoCamera", "Camera is not open.");
            end

            obj.ensureLiveFigure();

            if obj.liveEnabled
                image2D = obj.tryGetOneFrameOrTrigger();
            else
                image2D = obj.acquireOneFrameStandalone();
            end

            obj.updateLiveFigure(image2D);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            if isempty(obj.tlCamera)
                error("instrument_CS165MU:NoCamera", "Camera is not open.");
            end

            switch channelIndex
                case 1 % continuous
                    obj.pendingValue = double(obj.liveEnabled);
                case 2 % exposure_ms
                    obj.pendingValue = double(obj.tlCamera.ExposureTime_us) / 1000;
                case 3 % roi_origin_x_px
                    roiAndBin = obj.tlCamera.ROIAndBin;
                    obj.pendingValue = double(roiAndBin.ROIOriginX_pixels);
                case 4 % roi_origin_y_px
                    roiAndBin = obj.tlCamera.ROIAndBin;
                    obj.pendingValue = double(roiAndBin.ROIOriginY_pixels);
                case 5 % roi_width_px
                    roiAndBin = obj.tlCamera.ROIAndBin;
                    obj.pendingValue = double(roiAndBin.ROIWidth_pixels);
                case 6 % roi_height_px
                    roiAndBin = obj.tlCamera.ROIAndBin;
                    obj.pendingValue = double(roiAndBin.ROIHeight_pixels);
                case 7 % bin
                    roiAndBin = obj.tlCamera.ROIAndBin;
                    obj.pendingValue = double(roiAndBin.BinX);
                case 8 % queued_frames
                    obj.pendingValue = double(obj.tlCamera.NumberOfQueuedFrames);
                otherwise
                    error("instrument_CS165MU:UnknownChannelIndex", "Unknown channelIndex %d", channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case {1, 2, 3, 4, 5, 6, 7, 8}
                    getValues = obj.pendingValue;
                    obj.pendingValue = NaN;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if isempty(obj.tlCamera)
                error("instrument_CS165MU:NoCamera", "Camera is not open.");
            end

            switch channelIndex
                case 1 % continuous
                    enable = (setValues(1) ~= 0);
                    if enable
                        obj.startContinuousAcquisition();
                    else
                        obj.stopContinuousAcquisition();
                    end

                case 2 % exposure_ms
                    newExposure_ms = setValues(1);
                    if ~isfinite(newExposure_ms) || newExposure_ms <= 0
                        error("instrument_CS165MU:InvalidExposure", "exposure_ms must be positive and finite.");
                    end
                    wasLive = obj.liveEnabled;
                    if wasLive
                        obj.stopContinuousAcquisition();
                    end
                    obj.tlCamera.ExposureTime_us = uint32(max(1, round(newExposure_ms * 1000)));
                    if wasLive
                        obj.startContinuousAcquisition();
                    end

                case {3, 4, 5, 6, 7}
                    % ROI and bin settings are interdependent in the Thorlabs SDK
                    obj.setRoiOrBinScalarChannel(channelIndex, setValues(1));

                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end
    end

    methods (Access = private)
        function loadDotNetAssembliesAndPath(obj)
            classFile = which(class(obj));
            if isempty(classFile)
                error("instrument_CS165MU:ClassLookupFailed", "Unable to locate class file via which(class(obj)).");
            end
            instDir = fileparts(classFile);
            dllDir = fullfile(instDir, "dlls");
            if ~isfolder(dllDir)
                error("instrument_CS165MU:MissingDllFolder", "DLL folder not found at %s.", dllDir);
            end

            % Ensure the native DLL dependencies are discoverable.
            currentPath = string(getenv("PATH"));
            dllDirStr = string(dllDir);
            if ~contains(";" + currentPath + ";", ";" + dllDirStr + ";")
                setenv("PATH", dllDirStr + ";" + currentPath);
            end

            % Load .NET assemblies using absolute paths.
            if exist("Thorlabs.TSI.TLCamera.TLCameraSDK", "class") ~= 8
                tlCameraDll = fullfile(dllDir, "Thorlabs.TSI.TLCamera.dll");
                if ~isfile(tlCameraDll)
                    error("instrument_CS165MU:MissingAssembly", "Missing %s", tlCameraDll);
                end
                NET.addAssembly(tlCameraDll);
            end

            if exist("Thorlabs.TSI.TLCameraInterfaces.OperationMode", "class") ~= 8
                tlCameraInterfacesDll = fullfile(dllDir, "Thorlabs.TSI.TLCameraInterfaces.dll");
                if ~isfile(tlCameraInterfacesDll)
                    error("instrument_CS165MU:MissingAssembly", "Missing %s", tlCameraInterfacesDll);
                end
                NET.addAssembly(tlCameraInterfacesDll);
            end
        end

        function openCameraOrError(obj, requestedSerial)
            obj.tlCameraSDK = Thorlabs.TSI.TLCamera.TLCameraSDK.OpenTLCameraSDK;
            obj.serialNumbers = obj.tlCameraSDK.DiscoverAvailableCameras;

            if obj.serialNumbers.Count <= 0
                error("instrument_CS165MU:NoCameraFound", "No Thorlabs TLCamera detected by the SDK.");
            end

            requestedSerial = string(requestedSerial);
            if requestedSerial == ""
                chosenSerial = string(obj.serialNumbers.Item(0));
            else
                chosenSerial = requestedSerial;
                found = false;
                for k = 0:(obj.serialNumbers.Count - 1)
                    if string(obj.serialNumbers.Item(k)) == chosenSerial
                        found = true;
                        break;
                    end
                end
                if ~found
                    error("instrument_CS165MU:SerialNotFound", ...
                        "Requested camera serial %s not found. %d camera(s) discovered.", ...
                        chosenSerial, obj.serialNumbers.Count);
                end
            end

            obj.tlCamera = obj.tlCameraSDK.OpenCamera(chosenSerial, false);
            obj.communicationHandle = obj.tlCamera;
            obj.address = string(chosenSerial);

            % Cache public sensor size
            obj.sensorWidth_px = double(obj.tlCamera.SensorWidth_pixels);
            obj.sensorHeight_px = double(obj.tlCamera.SensorHeight_pixels);

            % Reasonable defaults for interactive tuning
            try
                obj.tlCamera.MaximumNumberOfFramesToQueue = 5;
            catch
            end
            try
                obj.tlCamera.OperationMode = Thorlabs.TSI.TLCameraInterfaces.OperationMode.SoftwareTriggered;
            catch
            end
            try
                obj.tlCamera.FramesPerTrigger_zeroForUnlimited = 1;
            catch
            end
        end

        function ensureLiveFigure(obj)
            if ~isempty(obj.liveFigure) && isvalid(obj.liveFigure)
                return;
            end

            obj.liveFigure = figure( ...
                Name = "CS165MU Live", ...
                NumberTitle = "off", ...
                Color = "w", ...
                HandleVisibility = "callback", ...
                CloseRequestFcn = @(h, e) obj.onLiveFigureCloseRequest(h, e));

            obj.liveAxes = axes(obj.liveFigure);
            colormap(obj.liveAxes, gray(256));
            obj.liveAxes.Box = "on";
            obj.liveAxes.XLabel.String = "x (px)";
            obj.liveAxes.YLabel.String = "y (px)";

            % Initialize image object
            obj.liveImage = imagesc(obj.liveAxes, zeros(10, 10, "uint16"));
            obj.liveAxes.YDir = "normal";
            axis(obj.liveAxes, "image"); % square pixels
            obj.liveAxes.Toolbar.Visible = "off";
            obj.liveFigure.Visible = "on";
            drawnow;
        end

        function onLiveFigureCloseRequest(obj, h, ~)
            % Stop live acquisition but do not delete the instrument.
            obj.stopContinuousAcquisition();
            try
                delete(h);
            catch
            end
        end

        function startContinuousAcquisition(obj)
            if obj.liveEnabled
                return;
            end
            obj.ensureLiveFigure();

            if isempty(obj.liveTimer) || ~isvalid(obj.liveTimer)
                obj.liveTimer = timer( ...
                    ExecutionMode = "fixedSpacing", ...
                    Period = 0.05, ...
                    BusyMode = "drop", ...
                    TimerFcn = @(~, ~) obj.liveTick());
            end

            % Arm for continuous software-triggered acquisition
            obj.tlCamera.OperationMode = Thorlabs.TSI.TLCameraInterfaces.OperationMode.SoftwareTriggered;
            obj.tlCamera.FramesPerTrigger_zeroForUnlimited = 0;
            if obj.tlCamera.IsArmed
                obj.tlCamera.Disarm;
            end
            obj.tlCamera.Arm;
            obj.tlCamera.IssueSoftwareTrigger;

            obj.liveEnabled = true;
            start(obj.liveTimer);
        end

        function stopContinuousAcquisition(obj)
            obj.liveEnabled = false;

            if ~isempty(obj.liveTimer) && isvalid(obj.liveTimer)
                try
                    stop(obj.liveTimer);
                catch
                end
            end

            if ~isempty(obj.tlCamera)
                try
                    if obj.tlCamera.IsArmed
                        obj.tlCamera.Disarm;
                    end
                catch
                end
            end
        end

        function liveTick(obj)
            if ~obj.liveEnabled
                return;
            end
            if isempty(obj.tlCamera) || isempty(obj.liveFigure) || ~isvalid(obj.liveFigure)
                obj.stopContinuousAcquisition();
                return;
            end

            try
                if obj.tlCamera.NumberOfQueuedFrames > 0
                    imageFrame = obj.tlCamera.GetPendingFrameOrNull;
                    if ~isempty(imageFrame)
                        image2D = obj.frameToImage2D(imageFrame);
                        obj.updateLiveFigure(image2D);
                        delete(imageFrame);
                    end
                end
                drawnow limitrate;
            catch
                % If the camera gets disconnected or the SDK errors, stop live mode.
                obj.stopContinuousAcquisition();
            end
        end

        function image2D = acquireOneFrameStandalone(obj)
            % Arms camera for a single frame and returns it, then disarms.
            obj.tlCamera.OperationMode = Thorlabs.TSI.TLCameraInterfaces.OperationMode.SoftwareTriggered;
            obj.tlCamera.FramesPerTrigger_zeroForUnlimited = 1;

            if obj.tlCamera.IsArmed
                obj.tlCamera.Disarm;
            end

            obj.tlCamera.Arm;
            cleanup = onCleanup(@() obj.safeDisarm());

            obj.tlCamera.IssueSoftwareTrigger;

            timeout_s = max(1, double(obj.tlCamera.ExposureTime_us) / 1e6 * 5);
            startTime = datetime("now");
            timeout = seconds(timeout_s);
            imageFrame = [];
            while datetime("now") - startTime < timeout
                if obj.tlCamera.NumberOfQueuedFrames > 0
                    imageFrame = obj.tlCamera.GetPendingFrameOrNull;
                    if ~isempty(imageFrame)
                        break;
                    end
                end
                pause(1E-6);
            end

            if isempty(imageFrame)
                error("instrument_CS165MU:AcquisitionTimeout", "Timed out waiting for image frame.");
            end

            image2D = obj.frameToImage2D(imageFrame);
            delete(imageFrame);
            clear cleanup;
        end

        function image2D = tryGetOneFrameOrTrigger(obj)
            % In continuous mode, attempt to read one pending frame; otherwise trigger and wait.
            imageFrame = [];
            if obj.tlCamera.NumberOfQueuedFrames > 0
                imageFrame = obj.tlCamera.GetPendingFrameOrNull;
            end

            if isempty(imageFrame)
                % Ensure acquisition is running and trigger once more.
                try
                    if ~obj.tlCamera.IsArmed
                        obj.tlCamera.Arm;
                        obj.tlCamera.IssueSoftwareTrigger;
                    else
                        obj.tlCamera.IssueSoftwareTrigger;
                    end
                catch
                end

                timeout_s = max(1, double(obj.tlCamera.ExposureTime_us) / 1e6 * 5);
                startTime = datetime("now");
                timeout = seconds(timeout_s);
                while datetime("now") - startTime < timeout
                    if obj.tlCamera.NumberOfQueuedFrames > 0
                        imageFrame = obj.tlCamera.GetPendingFrameOrNull;
                        if ~isempty(imageFrame)
                            break;
                        end
                    end
                    pause(1E-6);
                end
            end

            if isempty(imageFrame)
                error("instrument_CS165MU:AcquisitionTimeout", "Timed out waiting for image frame.");
            end

            image2D = obj.frameToImage2D(imageFrame);
            delete(imageFrame);
        end

        function image2D = frameToImage2D(~, imageFrame)
            % Convert TLCamera image frame to 2D uint16 (Height x Width)
            imageData = uint16(imageFrame.ImageData.ImageData_monoOrBGR);
            imageHeight = double(imageFrame.ImageData.Height_pixels);
            imageWidth = double(imageFrame.ImageData.Width_pixels);
            image2D = reshape(imageData, [imageWidth, imageHeight]).';
        end

        function updateLiveFigure(obj, image2D)
            if isempty(obj.liveFigure) || ~isvalid(obj.liveFigure)
                return;
            end
            if isempty(obj.liveImage) || ~isvalid(obj.liveImage)
                return;
            end

            obj.liveImage.CData = image2D;
            axis(obj.liveAxes, "image");
            obj.liveAxes.XLimMode = "auto";
            obj.liveAxes.YLimMode = "auto";
        end

        function safeDisarm(obj)
            if isempty(obj.tlCamera)
                return;
            end
            try
                if obj.tlCamera.IsArmed
                    obj.tlCamera.Disarm;
                end
            catch
            end
        end

        function setRoiOrBinScalarChannel(obj, channelIndex, newValue)
            % Scalar channels:
            % 3 roi_origin_x_px
            % 4 roi_origin_y_px
            % 5 roi_width_px
            % 6 roi_height_px
            % 7 bin  (enforced as BinX == BinY)
            newValue = double(newValue);

            wasLive = obj.liveEnabled;
            if wasLive
                obj.stopContinuousAcquisition();
            end

            roiAndBin = obj.tlCamera.ROIAndBin;
            switch channelIndex
                case 3
                    roiAndBin.ROIOriginX_pixels = int32(round(newValue));
                case 4
                    roiAndBin.ROIOriginY_pixels = int32(round(newValue));
                case 5
                    roiAndBin.ROIWidth_pixels = int32(round(newValue));
                case 6
                    roiAndBin.ROIHeight_pixels = int32(round(newValue));
                case 7
                    binVal = int32(round(newValue));
                    roiAndBin.BinX = binVal;
                    roiAndBin.BinY = binVal;
            end

            % Basic validity clamps
            if roiAndBin.ROIOriginX_pixels < 0
                roiAndBin.ROIOriginX_pixels = int32(0);
            end
            if roiAndBin.ROIOriginY_pixels < 0
                roiAndBin.ROIOriginY_pixels = int32(0);
            end
            if roiAndBin.ROIWidth_pixels < 1
                roiAndBin.ROIWidth_pixels = int32(1);
            end
            if roiAndBin.ROIHeight_pixels < 1
                roiAndBin.ROIHeight_pixels = int32(1);
            end
            if roiAndBin.BinX < 1
                roiAndBin.BinX = int32(1);
            end
            if roiAndBin.BinY < 1
                roiAndBin.BinY = int32(1);
            end

            % Enforce square binning always (helps keep pixel aspect simple)
            roiAndBin.BinY = roiAndBin.BinX;

            obj.tlCamera.ROIAndBin = roiAndBin;

            if wasLive
                obj.startContinuousAcquisition();
            end
        end
    end
end


