classdef virtualInstrument_attodryAutofocus < virtualInstrumentInterface
    % Virtual instrument for Attodry T/B control with optics references.

    properties
        tSetChannelName (1, 1) string
        bSetChannelName (1, 1) string
        tReadChannelName (1, 1) string
        bReadChannelName (1, 1) string

        cameraInstrumentFriendlyName (1, 1) string = "CS165MU"

        blockerPositionChannelName (1, 1) string = ""
        ndPositionChannelName (1, 1) string = ""
        bsCameraPositionChannelName (1, 1) string = ""
        bsLedPositionChannelName (1, 1) string = ""
        bsCameraSetConsistentlyChannelName (1, 1) string = ""
        bsLedSetConsistentlyChannelName (1, 1) string = ""
        ledRgbChannelName (1, 1) string = ""

        blockerBlockedDeg (1, 1) double = 180
        blockerUnblockedDeg (1, 1) double = 0
        ndOnDeg (1, 1) double = 180
        ndOffDeg (1, 1) double = 0

        bsCameraOnCommandDeg (1, 1) double = 180
        bsCameraOffCommandDeg (1, 1) double = 0
        bsLedOnCommandDeg (1, 1) double = 180
        bsLedOffCommandDeg (1, 1) double = 0

        ledOnRgb (3, 1) double = [1; 1; 1]

        tbTargetTolerance (2, 1) double {mustBePositive} = [0.1; 1E-2]
        targetWaitTimeout (1, 1) duration = minutes(20)
        compensationInterval (1, 1) duration = seconds(2)

        bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
        bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
        bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.3
        bsQuantizationDeg (1, 1) double {mustBePositive} = 0.1

        shiftFitTrimRatio (2, 1) double = [0.2; 0.2]
    end

    properties (SetAccess = private)
        targetT (1, 1) double = NaN
        targetB (1, 1) double = NaN

        referenceSampleImage
        referenceLaserOnSampleImage
        referenceLaserOnlyImage

        lastEstimatedOffset_px (2, 1) double = [0; 0]
    end

    properties (Access = private)
        bsCameraLikelyOnDeg (1, 1) double = NaN
        bsCameraLikelyOffDeg (1, 1) double = NaN
        bsLedLikelyOnDeg (1, 1) double = NaN
        bsLedLikelyOffDeg (1, 1) double = NaN

        referenceSampleInterpolant
        referenceShiftFitModel
        referenceFitSize_px (1, 2) double = [NaN, NaN]
        referenceFitTrim_px (1, 2) double = [NaN, NaN]
    end

    methods
        function obj = virtualInstrument_attodryAutofocus(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                masterRack (1, 1) instrumentRack
                NameValueArgs.tSetChannelName (1, 1) string
                NameValueArgs.bSetChannelName (1, 1) string
                NameValueArgs.tReadChannelName (1, 1) string = ""
                NameValueArgs.bReadChannelName (1, 1) string = ""

                NameValueArgs.cameraInstrumentFriendlyName (1, 1) string = "CS165MU"

                NameValueArgs.blockerPositionChannelName (1, 1) string = ""
                NameValueArgs.ndPositionChannelName (1, 1) string = ""
                NameValueArgs.bsCameraPositionChannelName (1, 1) string = ""
                NameValueArgs.bsLedPositionChannelName (1, 1) string = ""
                NameValueArgs.bsCameraSetConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.bsLedSetConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.ledRgbChannelName (1, 1) string = ""

                NameValueArgs.blockerBlockedDeg (1, 1) double = 180
                NameValueArgs.blockerUnblockedDeg (1, 1) double = 0
                NameValueArgs.ndOnDeg (1, 1) double = 180
                NameValueArgs.ndOffDeg (1, 1) double = 0

                NameValueArgs.bsCameraOnCommandDeg (1, 1) double = 180
                NameValueArgs.bsCameraOffCommandDeg (1, 1) double = 0
                NameValueArgs.bsLedOnCommandDeg (1, 1) double = 180
                NameValueArgs.bsLedOffCommandDeg (1, 1) double = 0

                NameValueArgs.ledOnRgb (3, 1) double = [1; 1; 1]

                NameValueArgs.tbTargetTolerance (2, 1) double {mustBePositive} = [0.1; 1E-2]
                NameValueArgs.targetWaitTimeout (1, 1) duration = minutes(20)
                NameValueArgs.compensationInterval (1, 1) duration = seconds(2)

                NameValueArgs.bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
                NameValueArgs.bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
                NameValueArgs.bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.3
                NameValueArgs.bsQuantizationDeg (1, 1) double {mustBePositive} = 0.1

                NameValueArgs.shiftFitTrimRatio (2, 1) double = [0.2; 0.2]
            end

            obj@virtualInstrumentInterface(address, masterRack);

            obj.tSetChannelName = NameValueArgs.tSetChannelName;
            obj.bSetChannelName = NameValueArgs.bSetChannelName;

            if strlength(NameValueArgs.tReadChannelName) == 0
                obj.tReadChannelName = obj.tSetChannelName;
            else
                obj.tReadChannelName = NameValueArgs.tReadChannelName;
            end
            if strlength(NameValueArgs.bReadChannelName) == 0
                obj.bReadChannelName = obj.bSetChannelName;
            else
                obj.bReadChannelName = NameValueArgs.bReadChannelName;
            end

            obj.cameraInstrumentFriendlyName = NameValueArgs.cameraInstrumentFriendlyName;

            obj.blockerPositionChannelName = NameValueArgs.blockerPositionChannelName;
            obj.ndPositionChannelName = NameValueArgs.ndPositionChannelName;
            obj.bsCameraPositionChannelName = NameValueArgs.bsCameraPositionChannelName;
            obj.bsLedPositionChannelName = NameValueArgs.bsLedPositionChannelName;
            obj.bsCameraSetConsistentlyChannelName = NameValueArgs.bsCameraSetConsistentlyChannelName;
            obj.bsLedSetConsistentlyChannelName = NameValueArgs.bsLedSetConsistentlyChannelName;
            obj.ledRgbChannelName = NameValueArgs.ledRgbChannelName;

            obj.blockerBlockedDeg = NameValueArgs.blockerBlockedDeg;
            obj.blockerUnblockedDeg = NameValueArgs.blockerUnblockedDeg;
            obj.ndOnDeg = NameValueArgs.ndOnDeg;
            obj.ndOffDeg = NameValueArgs.ndOffDeg;
            obj.bsCameraOnCommandDeg = NameValueArgs.bsCameraOnCommandDeg;
            obj.bsCameraOffCommandDeg = NameValueArgs.bsCameraOffCommandDeg;
            obj.bsLedOnCommandDeg = NameValueArgs.bsLedOnCommandDeg;
            obj.bsLedOffCommandDeg = NameValueArgs.bsLedOffCommandDeg;

            if any(NameValueArgs.ledOnRgb < 0 | NameValueArgs.ledOnRgb > 1)
                error("virtualInstrument_attodryAutofocus:InvalidLedOnRgb", ...
                    "ledOnRgb must be in [0, 1] for each component.");
            end
            obj.ledOnRgb = NameValueArgs.ledOnRgb;

            obj.tbTargetTolerance = NameValueArgs.tbTargetTolerance;
            obj.targetWaitTimeout = NameValueArgs.targetWaitTimeout;
            obj.compensationInterval = NameValueArgs.compensationInterval;

            obj.bsCalibrationCycles = NameValueArgs.bsCalibrationCycles;
            obj.bsSetMaxAttempts = NameValueArgs.bsSetMaxAttempts;
            obj.bsPositionToleranceDeg = NameValueArgs.bsPositionToleranceDeg;
            obj.bsQuantizationDeg = NameValueArgs.bsQuantizationDeg;

            if any(NameValueArgs.shiftFitTrimRatio <= 0 | NameValueArgs.shiftFitTrimRatio >= 0.6)
                error("virtualInstrument_attodryAutofocus:InvalidShiftFitTrimRatio", ...
                    "shiftFitTrimRatio values must be in (0, 0.6).");
            end
            obj.shiftFitTrimRatio = NameValueArgs.shiftFitTrimRatio;

            obj.assertChannelsExist(unique([obj.tSetChannelName; obj.bSetChannelName; obj.tReadChannelName; obj.bReadChannelName]));

            obj.addChannel("T", setTolerances = obj.tbTargetTolerance(1));
            obj.addChannel("B", setTolerances = obj.tbTargetTolerance(2));

            currentTB = obj.getCurrentTB();
            obj.targetT = currentTB(1);
            obj.targetB = currentTB(2);
        end

        function positions = characterizeBeamSplitterEndpoints(obj)
            obj.assertOpticsChannelsConfigured();

            rack = obj.getMasterRack();
            rack.rackSet([obj.bsCameraSetConsistentlyChannelName; obj.bsLedSetConsistentlyChannelName], [1; 1]);

            [cameraOnDeg, cameraOffDeg] = obj.measureLikelyEndpoints( ...
                obj.bsCameraPositionChannelName, obj.bsCameraOnCommandDeg, obj.bsCameraOffCommandDeg);
            [ledOnDeg, ledOffDeg] = obj.measureLikelyEndpoints( ...
                obj.bsLedPositionChannelName, obj.bsLedOnCommandDeg, obj.bsLedOffCommandDeg);

            obj.bsCameraLikelyOnDeg = cameraOnDeg;
            obj.bsCameraLikelyOffDeg = cameraOffDeg;
            obj.bsLedLikelyOnDeg = ledOnDeg;
            obj.bsLedLikelyOffDeg = ledOffDeg;

            positions = struct( ...
                "cameraOnDeg", cameraOnDeg, ...
                "cameraOffDeg", cameraOffDeg, ...
                "ledOnDeg", ledOnDeg, ...
                "ledOffDeg", ledOffDeg);
        end

        function setBeamSplitterState(obj, beamSplitterName, isOn)
            arguments
                obj
                beamSplitterName (1, 1) string {mustBeMember(beamSplitterName, ["camera", "led"])}
                isOn (1, 1) logical
            end

            switch beamSplitterName
                case "camera"
                    positionChannelName = obj.bsCameraPositionChannelName;
                    setConsistentChannelName = obj.bsCameraSetConsistentlyChannelName;
                    if isOn
                        targetLikelyDeg = obj.bsCameraLikelyOnDeg;
                        commandDeg = obj.bsCameraOnCommandDeg;
                    else
                        targetLikelyDeg = obj.bsCameraLikelyOffDeg;
                        commandDeg = obj.bsCameraOffCommandDeg;
                    end
                case "led"
                    positionChannelName = obj.bsLedPositionChannelName;
                    setConsistentChannelName = obj.bsLedSetConsistentlyChannelName;
                    if isOn
                        targetLikelyDeg = obj.bsLedLikelyOnDeg;
                        commandDeg = obj.bsLedOnCommandDeg;
                    else
                        targetLikelyDeg = obj.bsLedLikelyOffDeg;
                        commandDeg = obj.bsLedOffCommandDeg;
                    end
            end

            if ~isfinite(targetLikelyDeg)
                error("virtualInstrument_attodryAutofocus:BeamSplitterEndpointsMissing", ...
                    "Call characterizeBeamSplitterEndpoints() before setBeamSplitterState().");
            end

            rack = obj.getMasterRack();
            rack.rackSet(setConsistentChannelName, 1);

            for attemptIndex = 1:obj.bsSetMaxAttempts
                rack.rackSet(positionChannelName, commandDeg);
                measuredDeg = rack.rackGet(positionChannelName);
                if abs(measuredDeg - targetLikelyDeg) <= obj.bsPositionToleranceDeg
                    return;
                end
                if attemptIndex == obj.bsSetMaxAttempts
                    error("virtualInstrument_attodryAutofocus:BeamSplitterRetryFailed", ...
                        "%s BS failed to reach %.4g deg after %d attempts. Last read: %.4g deg.", ...
                        beamSplitterName, targetLikelyDeg, obj.bsSetMaxAttempts, measuredDeg);
                end
            end
        end

        function references = takeReferenceData(obj)
            obj.characterizeBeamSplitterEndpoints();

            % 1) Sample image: laser blocked, both BS on, LED on
            obj.setBeamSplitterState("camera", true);
            obj.setBeamSplitterState("led", true);
            obj.setLaserPathState(blocked = true, ndOn = false);
            obj.setLedState(true);
            sampleImage = obj.acquireCameraImage();

            % 2) Laser on sample: ND on, blocker open
            obj.setBeamSplitterState("camera", true);
            obj.setBeamSplitterState("led", true);
            obj.setLaserPathState(blocked = false, ndOn = true);
            obj.setLedState(true);
            laserOnSampleImage = obj.acquireCameraImage();

            % 3) Laser only: LED BS off, LED off
            obj.setBeamSplitterState("camera", true);
            obj.setBeamSplitterState("led", false);
            obj.setLaserPathState(blocked = false, ndOn = true);
            obj.setLedState(false);
            laserOnlyImage = obj.acquireCameraImage();

            obj.referenceSampleImage = sampleImage;
            obj.referenceLaserOnSampleImage = laserOnSampleImage;
            obj.referenceLaserOnlyImage = laserOnlyImage;
            obj.buildReferenceFitModel();

            obj.setLaserPathState(blocked = true, ndOn = false);
            obj.setLedState(false);

            references = struct( ...
                "sampleImage", sampleImage, ...
                "laserOnSampleImage", laserOnSampleImage, ...
                "laserOnlyImage", laserOnlyImage, ...
                "cameraBsLikelyOnDeg", obj.bsCameraLikelyOnDeg, ...
                "cameraBsLikelyOffDeg", obj.bsCameraLikelyOffDeg, ...
                "ledBsLikelyOnDeg", obj.bsLedLikelyOnDeg, ...
                "ledBsLikelyOffDeg", obj.bsLedLikelyOffDeg);
        end

        function [dx, dy, gof] = estimateSampleOffset(obj, image2D)
            obj.assertReferenceFitReady();

            if ~isequal(size(image2D), obj.referenceFitSize_px)
                error("virtualInstrument_attodryAutofocus:ImageSizeMismatch", ...
                    "Expected image size [%d, %d], received [%d, %d].", ...
                    obj.referenceFitSize_px(1), obj.referenceFitSize_px(2), size(image2D, 1), size(image2D, 2));
            end

            filtered = log(double(image2D) + 1);
            [rows, cols] = size(filtered);
            [xGrid, yGrid] = ndgrid(1:rows, 1:cols);

            xTrim = obj.referenceFitTrim_px(1);
            yTrim = obj.referenceFitTrim_px(2);
            xGridTrimmed = xGrid(xTrim+1:end-xTrim, yTrim+1:end-yTrim);
            yGridTrimmed = yGrid(xTrim+1:end-xTrim, yTrim+1:end-yTrim);
            zGridTrimmed = filtered(xTrim+1:end-xTrim, yTrim+1:end-yTrim);

            xColumn = xGridTrimmed(:);
            yColumn = yGridTrimmed(:);
            zColumn = zGridTrimmed(:);

            [fitResult, gof] = fit([xColumn, yColumn], zColumn, obj.referenceShiftFitModel, ...
                StartPoint = [0, 0], ...
                Lower = [-xTrim, -yTrim], ...
                Upper = [xTrim, yTrim], ...
                DiffMinChange = 0.00001, ...
                TolFun = 0.001, ...
                TolX = 0.001);

            dx = fitResult.dx;
            dy = fitResult.dy;
        end

        function result = performAutofocusAndAutoshift(obj)
            % Placeholder: estimate image shift but do not yet actuate correction.
            result = struct("didApplyCorrection", false, "dx_px", NaN, "dy_px", NaN);

            if isempty(obj.referenceSampleImage)
                return;
            end

            liveImage = obj.acquireCameraImage();
            [dx, dy] = obj.estimateSampleOffset(liveImage);
            obj.lastEstimatedOffset_px = [dx; dy];

            result.dx_px = dx;
            result.dy_px = dy;
        end
    end

    methods (Access = ?instrumentInterface)
        function getValues = getReadChannelHelper(obj, channelIndex)
            currentTB = obj.getCurrentTB();
            switch channelIndex
                case 1
                    getValues = currentTB(1);
                case 2
                    getValues = currentTB(2);
                otherwise
                    error("virtualInstrument_attodryAutofocus:UnsupportedReadChannel", ...
                        "Unsupported read channel index %d.", channelIndex);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    obj.targetT = setValues(1);
                case 2
                    obj.targetB = setValues(1);
                otherwise
                    setWriteChannelHelper@virtualInstrumentInterface(obj, channelIndex, setValues);
            end
            obj.waitForTargetsWithCompensation();
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            currentTB = obj.getCurrentTB();
            switch channelIndex
                case 1
                    TF = abs(currentTB(1) - obj.targetT) <= obj.tbTargetTolerance(1);
                case 2
                    TF = abs(currentTB(2) - obj.targetB) <= obj.tbTargetTolerance(2);
                otherwise
                    TF = true;
            end
        end
    end

    methods (Access = private)
        function waitForTargetsWithCompensation(obj)
            rack = obj.getMasterRack();
            rack.rackSetWrite([obj.tSetChannelName; obj.bSetChannelName], [obj.targetT; obj.targetB]);

            deadline = datetime("now") + obj.targetWaitTimeout;
            while true
                currentTB = obj.getCurrentTB();
                if obj.targetsReached(currentTB)
                    return;
                end

                obj.performAutofocusAndAutoshift();

                if datetime("now") >= deadline
                    error("virtualInstrument_attodryAutofocus:TargetTimeout", ...
                        "Timed out waiting for T/B targets. Target=[%.6g, %.6g], current=[%.6g, %.6g].", ...
                        obj.targetT, obj.targetB, currentTB(1), currentTB(2));
                end

                if obj.compensationInterval > seconds(0)
                    pause(seconds(obj.compensationInterval));
                end
            end
        end

        function TF = targetsReached(obj, currentTB)
            TF = abs(currentTB(1) - obj.targetT) <= obj.tbTargetTolerance(1) ...
                && abs(currentTB(2) - obj.targetB) <= obj.tbTargetTolerance(2);
        end

        function currentTB = getCurrentTB(obj)
            rack = obj.getMasterRack();
            currentTB = rack.rackGet([obj.tReadChannelName; obj.bReadChannelName]);
            currentTB = currentTB(:);
            if numel(currentTB) ~= 2
                error("virtualInstrument_attodryAutofocus:UnexpectedTBReadLength", ...
                    "Expected 2 values from [T, B] read channels.");
            end
        end

        function setLaserPathState(obj, NameValueArgs)
            arguments
                obj
                NameValueArgs.blocked (1, 1) logical
                NameValueArgs.ndOn (1, 1) logical
            end

            blockerTargetDeg = obj.blockerUnblockedDeg;
            if NameValueArgs.blocked
                blockerTargetDeg = obj.blockerBlockedDeg;
            end

            ndTargetDeg = obj.ndOffDeg;
            if NameValueArgs.ndOn
                ndTargetDeg = obj.ndOnDeg;
            end

            rack = obj.getMasterRack();
            rack.rackSet([obj.blockerPositionChannelName; obj.ndPositionChannelName], [blockerTargetDeg; ndTargetDeg]);
        end

        function setLedState(obj, ledOn)
            if ledOn
                rgb = obj.ledOnRgb;
            else
                rgb = [0; 0; 0];
            end

            if any(rgb < 0 | rgb > 1)
                error("virtualInstrument_attodryAutofocus:InvalidLedRgb", ...
                    "RGB values must be in [0, 1].");
            end

            rack = obj.getMasterRack();
            rack.rackSet(obj.ledRgbChannelName, rgb);
        end

        function [likelyOnDeg, likelyOffDeg] = measureLikelyEndpoints(obj, positionChannelName, onCommandDeg, offCommandDeg)
            rack = obj.getMasterRack();

            onSamples = zeros(obj.bsCalibrationCycles, 1);
            offSamples = zeros(obj.bsCalibrationCycles, 1);

            for cycleIndex = 1:obj.bsCalibrationCycles
                rack.rackSet(positionChannelName, offCommandDeg);
                offSamples(cycleIndex) = rack.rackGet(positionChannelName);

                rack.rackSet(positionChannelName, onCommandDeg);
                onSamples(cycleIndex) = rack.rackGet(positionChannelName);
            end

            likelyOnDeg = obj.pickLikelyPosition(onSamples);
            likelyOffDeg = obj.pickLikelyPosition(offSamples);
        end

        function likelyDeg = pickLikelyPosition(obj, samplesDeg)
            if any(~isfinite(samplesDeg))
                error("virtualInstrument_attodryAutofocus:InvalidBeamSplitterSample", ...
                    "Measured beam splitter positions must be finite.");
            end
            quantized = round(samplesDeg / obj.bsQuantizationDeg) * obj.bsQuantizationDeg;
            likelyDeg = mode(quantized);
        end

        function image2D = acquireCameraImage(obj)
            rack = obj.getMasterRack();
            mask = rack.instrumentTable.instrumentFriendlyNames == obj.cameraInstrumentFriendlyName;
            if ~any(mask)
                error("virtualInstrument_attodryAutofocus:MissingCameraInstrument", ...
                    "Camera instrument ""%s"" was not found in rack.instrumentTable.", obj.cameraInstrumentFriendlyName);
            end

            cameraHandle = rack.instrumentTable.instruments(find(mask, 1, "first"));
            if ~ismethod(cameraHandle, "acquireSingleImage")
                error("virtualInstrument_attodryAutofocus:CameraMethodMissing", ...
                    "Camera instrument ""%s"" must expose acquireSingleImage().", obj.cameraInstrumentFriendlyName);
            end

            image2D = cameraHandle.acquireSingleImage();
        end

        function buildReferenceFitModel(obj)
            if exist("fit", "file") ~= 2
                error("virtualInstrument_attodryAutofocus:MissingCurveFittingToolbox", ...
                    "takeReferenceData requires Curve Fitting Toolbox (fit).");
            end

            referenceFiltered = log(double(obj.referenceSampleImage) + 1);
            [rows, cols] = size(referenceFiltered);

            xTrim = ceil(obj.shiftFitTrimRatio(1) / 2 * rows);
            yTrim = ceil(obj.shiftFitTrimRatio(2) / 2 * cols);
            if xTrim * 2 >= rows || yTrim * 2 >= cols
                error("virtualInstrument_attodryAutofocus:TrimTooLarge", ...
                    "shiftFitTrimRatio trims away the full image.");
            end

            [xGrid, yGrid] = ndgrid(1:rows, 1:cols);
            obj.referenceSampleInterpolant = griddedInterpolant(xGrid, yGrid, referenceFiltered, "spline", "none");
            obj.referenceShiftFitModel = @(dx, dy, x, y) obj.referenceSampleInterpolant(x + dx, y + dy);
            obj.referenceFitSize_px = [rows, cols];
            obj.referenceFitTrim_px = [xTrim, yTrim];
        end

        function assertReferenceFitReady(obj)
            if isempty(obj.referenceSampleImage) || isempty(obj.referenceShiftFitModel)
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before estimating sample offsets.");
            end
        end

        function assertChannelsExist(obj, channelNames)
            rack = obj.getMasterRack();
            channelNames = unique(channelNames(:));
            available = rack.channelTable.channelFriendlyNames;
            missing = channelNames(~ismember(channelNames, available));
            if ~isempty(missing)
                error("virtualInstrument_attodryAutofocus:MissingRackChannels", ...
                    "These rack channels are missing: %s", strjoin(missing, ", "));
            end
        end

        function assertOpticsChannelsConfigured(obj)
            labels = [ ...
                "blockerPositionChannelName"; ...
                "ndPositionChannelName"; ...
                "bsCameraPositionChannelName"; ...
                "bsLedPositionChannelName"; ...
                "bsCameraSetConsistentlyChannelName"; ...
                "bsLedSetConsistentlyChannelName"; ...
                "ledRgbChannelName"];

            values = [ ...
                obj.blockerPositionChannelName; ...
                obj.ndPositionChannelName; ...
                obj.bsCameraPositionChannelName; ...
                obj.bsLedPositionChannelName; ...
                obj.bsCameraSetConsistentlyChannelName; ...
                obj.bsLedSetConsistentlyChannelName; ...
                obj.ledRgbChannelName];

            missingConfigMask = strlength(values) == 0;
            if any(missingConfigMask)
                error("virtualInstrument_attodryAutofocus:MissingOpticsConfiguration", ...
                    "Set these constructor NameValueArgs before optics operations: %s", ...
                    strjoin(labels(missingConfigMask), ", "));
            end

            obj.assertChannelsExist(values);
        end
    end
end
