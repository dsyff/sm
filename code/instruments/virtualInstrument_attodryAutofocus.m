classdef virtualInstrument_attodryAutofocus < virtualInstrumentInterface
    % Virtual instrument for Attodry T/B control with optics references.

    properties
        T_channelName (1, 1) string
        B_channelName (1, 1) string

        cameraInstrumentFriendlyName (1, 1) string = "CS165MU"

        block_red_positionChannelName (1, 1) string = ""
        block_green_positionChannelName (1, 1) string = ""
        ND_red_positionChannelName (1, 1) string = ""
        ND_green_positionChannelName (1, 1) string = ""
        BS_camera_positionChannelName (1, 1) string = ""
        BS_LED_positionChannelName (1, 1) string = ""
        BS_camera_setConsistentlyChannelName (1, 1) string = ""
        BS_LED_setConsistentlyChannelName (1, 1) string = ""
        ledRgbChannelName (1, 1) string = ""

        block_red_blocked_PositionDeg (1, 1) double = 180
        block_red_unblocked_PositionDeg (1, 1) double = 0
        block_green_blocked_PositionDeg (1, 1) double = 180
        block_green_unblocked_PositionDeg (1, 1) double = 0
        ND_red_on_PositionDeg (1, 1) double = 180
        ND_red_off_PositionDeg (1, 1) double = 0
        ND_green_on_PositionDeg (1, 1) double = 180
        ND_green_off_PositionDeg (1, 1) double = 0
        BS_camera_on_PositionDeg (1, 1) double = 180
        BS_camera_off_PositionDeg (1, 1) double = 0
        BS_LED_on_PositionDeg (1, 1) double = 180
        BS_LED_off_PositionDeg (1, 1) double = 0

        tbTargetTolerance (2, 1) double {mustBePositive} = [0.1; 1E-2]
        targetWaitTimeout (1, 1) duration = minutes(20)
        compensationInterval (1, 1) duration = seconds(2)
        noCorrectionQuietDuration (1, 1) duration = minutes(1)
        temperatureStableWindow (1, 1) duration = minutes(10)
        temperatureStableSlopeTolerance_K_per_min (1, 1) double {mustBeNonnegative} = 0.050

        bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
        bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
        bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.3
        % Binning step (deg) in pickLikelyPosition when finding BS endpoint from repeated reads. Default = 1 tick (4096 ticks/360°).
        bsQuantizationDeg (1, 1) double {mustBePositive} = 360 / 4096

        shiftFitTrimRatio (2, 1) double = [0.2; 0.2]
        offsetFitRoi_px (1, 4) double = [NaN, NaN, NaN, NaN]  % [x, y, width, height]

        % ANC300 nanopositioner (optional). Empty = no autofocus/autoshift actuation.
        ANC300InstrumentFriendlyName (1, 1) string = ""
        ANC300_voltage_x_ChannelName (1, 1) string = ""
        ANC300_voltage_y_ChannelName (1, 1) string = ""
        ANC300_voltage_z_ChannelName (1, 1) string = ""

        % Initial voltages (V) by temperature regime. 1=300K, 2=77K, 3=4K, 4=~1K. ANPx101/LT (XY) and ANPz102/LT (Z); stored higher value of range.
        initialVoltage_xy (4, 1) double = [20; 30; 45; 50]
        initialVoltage_z (4, 1) double = [25; 35; 50; 55]
        temperatureRegime (1, 1) double {mustBeInteger, mustBeMember(temperatureRegime, [1, 2, 3, 4])} = 4
        positionerVoltageProfileCsvPath (1, 1) string = ""

        tenengradThreshold (1, 1) double {mustBeNonnegative} = 1e-4
        maxAutofocusIterations (1, 1) double {mustBeInteger, mustBePositive} = 50
        zVoltageIncrementFactor (1, 1) double {mustBePositive} = 1.2
        zStepTrialCount (1, 1) double {mustBeInteger, mustBePositive} = 5

        targetStepSizePixel (1, 1) double {mustBePositive} = 0.5
        cameraVerifiableStepSizePixel (1, 1) double {mustBePositive} = 1.0
        autoshiftStepRatio (1, 1) double {mustBePositive} = 0.5
        xyResponseMatrixMinRcond (1, 1) double {mustBePositive} = 1e-3
        maxAutoshiftCalibrationSteps (1, 1) double {mustBeInteger, mustBePositive} = 20
    end

    properties (SetAccess = private)
        targetT (1, 1) double = NaN
        targetB (1, 1) double = NaN
        colorStored (1, 1) double = 0  % 0 = red, 1 = green

        referenceSampleImage
        referenceLaserOnSampleImage
        referenceLaserOnlyImage

        lastEstimatedOffset_px (2, 1) double = [0; 0]
    end

    properties (Access = private)
        BS_camera_likelyOn_PositionDeg (1, 1) double = NaN
        BS_camera_likelyOff_PositionDeg (1, 1) double = NaN
        BS_LED_likelyOn_PositionDeg (1, 1) double = NaN
        BS_LED_likelyOff_PositionDeg (1, 1) double = NaN

        referenceSampleInterpolant
        referenceShiftFitModel
        referenceFitSize_px (1, 2) double = [NaN, NaN]
        referenceFitTrim_px (1, 2) double = [NaN, NaN]

        xyPixelPerStepMatrix (2, 2) double = NaN(2, 2)
        nextCorrectionKind (1, 1) string = "xy"
        voltageProfileMinTemperatureSpacing_K (1, 1) double {mustBePositive} = 5
        voltageProfileUpdateFractionThreshold (1, 1) double {mustBePositive} = 0.20
    end

    methods
        function obj = virtualInstrument_attodryAutofocus(address, masterRackProxy, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                masterRackProxy (1, 1) instrumentRackProxy
                NameValueArgs.T_channelName (1, 1) string
                NameValueArgs.B_channelName (1, 1) string

                NameValueArgs.cameraInstrumentFriendlyName (1, 1) string = "CS165MU"

                NameValueArgs.block_red_positionChannelName (1, 1) string = ""
                NameValueArgs.block_green_positionChannelName (1, 1) string = ""
                NameValueArgs.ND_red_positionChannelName (1, 1) string = ""
                NameValueArgs.ND_green_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_camera_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_LED_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_camera_setConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.BS_LED_setConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.ledRgbChannelName (1, 1) string = ""

                NameValueArgs.block_red_blocked_PositionDeg (1, 1) double = 180
                NameValueArgs.block_red_unblocked_PositionDeg (1, 1) double = 0
                NameValueArgs.block_green_blocked_PositionDeg (1, 1) double = 180
                NameValueArgs.block_green_unblocked_PositionDeg (1, 1) double = 0
                NameValueArgs.ND_red_on_PositionDeg (1, 1) double = 180
                NameValueArgs.ND_red_off_PositionDeg (1, 1) double = 0
                NameValueArgs.ND_green_on_PositionDeg (1, 1) double = 180
                NameValueArgs.ND_green_off_PositionDeg (1, 1) double = 0
                NameValueArgs.BS_camera_on_PositionDeg (1, 1) double = 180
                NameValueArgs.BS_camera_off_PositionDeg (1, 1) double = 0
                NameValueArgs.BS_LED_on_PositionDeg (1, 1) double = 180
                NameValueArgs.BS_LED_off_PositionDeg (1, 1) double = 0

                NameValueArgs.tbTargetTolerance (2, 1) double {mustBePositive} = [0.1; 1E-2]
                NameValueArgs.targetWaitTimeout (1, 1) duration = minutes(20)
                NameValueArgs.compensationInterval (1, 1) duration = seconds(2)
                NameValueArgs.noCorrectionQuietDuration (1, 1) duration = minutes(1)
                NameValueArgs.temperatureStableWindow (1, 1) duration = minutes(10)
                NameValueArgs.temperatureStableSlopeTolerance_K_per_min (1, 1) double {mustBeNonnegative} = 0.050

                NameValueArgs.bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
                NameValueArgs.bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
                NameValueArgs.bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.08
                NameValueArgs.bsQuantizationDeg (1, 1) double {mustBePositive} = 360 / 4096

                NameValueArgs.shiftFitTrimRatio (2, 1) double = [0.2; 0.2]
                NameValueArgs.offsetFitRoi_px (1, 4) double = [NaN, NaN, NaN, NaN]

                NameValueArgs.ANC300InstrumentFriendlyName (1, 1) string = ""
                NameValueArgs.ANC300_voltage_x_ChannelName (1, 1) string = ""
                NameValueArgs.ANC300_voltage_y_ChannelName (1, 1) string = ""
                NameValueArgs.ANC300_voltage_z_ChannelName (1, 1) string = ""
                NameValueArgs.initialVoltage_xy (4, 1) double = [20; 30; 45; 50]
                NameValueArgs.initialVoltage_z (4, 1) double = [25; 35; 50; 55]
                NameValueArgs.temperatureRegime (1, 1) double {mustBeInteger, mustBePositive} = 4
                NameValueArgs.positionerVoltageProfileCsvPath (1, 1) string = ""
                NameValueArgs.tenengradThreshold (1, 1) double {mustBeNonnegative} = 1e-4
                NameValueArgs.maxAutofocusIterations (1, 1) double {mustBeInteger, mustBePositive} = 50
                NameValueArgs.zVoltageIncrementFactor (1, 1) double {mustBePositive} = 1.2
                NameValueArgs.zStepTrialCount (1, 1) double {mustBeInteger, mustBePositive} = 5
                NameValueArgs.targetStepSizePixel (1, 1) double {mustBePositive} = 0.5
                NameValueArgs.cameraVerifiableStepSizePixel (1, 1) double {mustBePositive} = 1.0
                NameValueArgs.autoshiftStepRatio (1, 1) double {mustBePositive} = 0.5
                NameValueArgs.xyResponseMatrixMinRcond (1, 1) double {mustBePositive} = 1e-3
                NameValueArgs.maxAutoshiftCalibrationSteps (1, 1) double {mustBeInteger, mustBePositive} = 20
            end

            obj@virtualInstrumentInterface(address, masterRackProxy);

            obj.T_channelName = NameValueArgs.T_channelName;
            obj.B_channelName = NameValueArgs.B_channelName;

            obj.cameraInstrumentFriendlyName = NameValueArgs.cameraInstrumentFriendlyName;

            obj.block_red_positionChannelName = NameValueArgs.block_red_positionChannelName;
            obj.block_green_positionChannelName = NameValueArgs.block_green_positionChannelName;
            obj.ND_red_positionChannelName = NameValueArgs.ND_red_positionChannelName;
            obj.ND_green_positionChannelName = NameValueArgs.ND_green_positionChannelName;
            obj.BS_camera_positionChannelName = NameValueArgs.BS_camera_positionChannelName;
            obj.BS_LED_positionChannelName = NameValueArgs.BS_LED_positionChannelName;
            obj.BS_camera_setConsistentlyChannelName = NameValueArgs.BS_camera_setConsistentlyChannelName;
            obj.BS_LED_setConsistentlyChannelName = NameValueArgs.BS_LED_setConsistentlyChannelName;
            obj.ledRgbChannelName = NameValueArgs.ledRgbChannelName;

            obj.block_red_blocked_PositionDeg = NameValueArgs.block_red_blocked_PositionDeg;
            obj.block_red_unblocked_PositionDeg = NameValueArgs.block_red_unblocked_PositionDeg;
            obj.block_green_blocked_PositionDeg = NameValueArgs.block_green_blocked_PositionDeg;
            obj.block_green_unblocked_PositionDeg = NameValueArgs.block_green_unblocked_PositionDeg;
            obj.ND_red_on_PositionDeg = NameValueArgs.ND_red_on_PositionDeg;
            obj.ND_red_off_PositionDeg = NameValueArgs.ND_red_off_PositionDeg;
            obj.ND_green_on_PositionDeg = NameValueArgs.ND_green_on_PositionDeg;
            obj.ND_green_off_PositionDeg = NameValueArgs.ND_green_off_PositionDeg;
            obj.BS_camera_on_PositionDeg = NameValueArgs.BS_camera_on_PositionDeg;
            obj.BS_camera_off_PositionDeg = NameValueArgs.BS_camera_off_PositionDeg;
            obj.BS_LED_on_PositionDeg = NameValueArgs.BS_LED_on_PositionDeg;
            obj.BS_LED_off_PositionDeg = NameValueArgs.BS_LED_off_PositionDeg;

            obj.tbTargetTolerance = NameValueArgs.tbTargetTolerance;
            obj.targetWaitTimeout = NameValueArgs.targetWaitTimeout;
            obj.compensationInterval = NameValueArgs.compensationInterval;
            obj.noCorrectionQuietDuration = NameValueArgs.noCorrectionQuietDuration;
            obj.temperatureStableWindow = NameValueArgs.temperatureStableWindow;
            obj.temperatureStableSlopeTolerance_K_per_min = NameValueArgs.temperatureStableSlopeTolerance_K_per_min;

            obj.bsCalibrationCycles = NameValueArgs.bsCalibrationCycles;
            obj.bsSetMaxAttempts = NameValueArgs.bsSetMaxAttempts;
            obj.bsPositionToleranceDeg = NameValueArgs.bsPositionToleranceDeg;
            obj.bsQuantizationDeg = NameValueArgs.bsQuantizationDeg;

            if any(NameValueArgs.shiftFitTrimRatio <= 0 | NameValueArgs.shiftFitTrimRatio >= 0.6)
                error("virtualInstrument_attodryAutofocus:InvalidShiftFitTrimRatio", ...
                    "shiftFitTrimRatio values must be in (0, 0.6).");
            end
            obj.shiftFitTrimRatio = NameValueArgs.shiftFitTrimRatio;
            obj.offsetFitRoi_px = NameValueArgs.offsetFitRoi_px;

            obj.ANC300InstrumentFriendlyName = NameValueArgs.ANC300InstrumentFriendlyName;
            obj.ANC300_voltage_x_ChannelName = NameValueArgs.ANC300_voltage_x_ChannelName;
            obj.ANC300_voltage_y_ChannelName = NameValueArgs.ANC300_voltage_y_ChannelName;
            obj.ANC300_voltage_z_ChannelName = NameValueArgs.ANC300_voltage_z_ChannelName;
            obj.initialVoltage_xy = NameValueArgs.initialVoltage_xy;
            obj.initialVoltage_z = NameValueArgs.initialVoltage_z;
            tr = NameValueArgs.temperatureRegime;
            if tr < 1 || tr > 4 || tr ~= round(tr)
                error("virtualInstrument_attodryAutofocus:InvalidTemperatureRegime", ...
                    "temperatureRegime must be 1 (300K), 2 (77K), 3 (4K), or 4 (~1K).");
            end
            obj.temperatureRegime = tr;
            if strlength(NameValueArgs.positionerVoltageProfileCsvPath) == 0
                obj.positionerVoltageProfileCsvPath = fullfile(fileparts(mfilename("fullpath")), ...
                    "attodry_autofocus_positioner_voltage_profile.csv");
            else
                obj.positionerVoltageProfileCsvPath = NameValueArgs.positionerVoltageProfileCsvPath;
            end
            obj.tenengradThreshold = NameValueArgs.tenengradThreshold;
            obj.maxAutofocusIterations = NameValueArgs.maxAutofocusIterations;
            obj.zVoltageIncrementFactor = NameValueArgs.zVoltageIncrementFactor;
            obj.zStepTrialCount = NameValueArgs.zStepTrialCount;
            obj.targetStepSizePixel = NameValueArgs.targetStepSizePixel;
            obj.cameraVerifiableStepSizePixel = NameValueArgs.cameraVerifiableStepSizePixel;
            obj.autoshiftStepRatio = NameValueArgs.autoshiftStepRatio;
            obj.xyResponseMatrixMinRcond = NameValueArgs.xyResponseMatrixMinRcond;
            obj.maxAutoshiftCalibrationSteps = NameValueArgs.maxAutoshiftCalibrationSteps;

            if strlength(obj.ANC300InstrumentFriendlyName) > 0
                obj.assertChannelsExist([obj.ANC300_voltage_x_ChannelName; obj.ANC300_voltage_y_ChannelName; obj.ANC300_voltage_z_ChannelName]);
            end

            obj.assertChannelsExist([obj.T_channelName; obj.B_channelName]);

            obj.addChannel("T", setTolerances = obj.tbTargetTolerance(1));
            obj.addChannel("B", setTolerances = obj.tbTargetTolerance(2));
            obj.addChannel("color");  % 0 = red, 1 = green

            currentTB = obj.getCurrentTB();
            obj.targetT = currentTB(1);
            obj.targetB = currentTB(2);
        end

        function positions = characterizeBeamSplitterEndpoints(obj)
            obj.assertOpticsChannelsConfigured();

            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSet([obj.BS_camera_setConsistentlyChannelName; obj.BS_LED_setConsistentlyChannelName], [1; 1]);

            [cameraOnDeg, cameraOffDeg] = obj.measureLikelyEndpoints( ...
                obj.BS_camera_positionChannelName, obj.BS_camera_on_PositionDeg, obj.BS_camera_off_PositionDeg);
            [ledOnDeg, ledOffDeg] = obj.measureLikelyEndpoints( ...
                obj.BS_LED_positionChannelName, obj.BS_LED_on_PositionDeg, obj.BS_LED_off_PositionDeg);

            obj.BS_camera_likelyOn_PositionDeg = cameraOnDeg;
            obj.BS_camera_likelyOff_PositionDeg = cameraOffDeg;
            obj.BS_LED_likelyOn_PositionDeg = ledOnDeg;
            obj.BS_LED_likelyOff_PositionDeg = ledOffDeg;

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
                    positionChannelName = obj.BS_camera_positionChannelName;
                    setConsistentChannelName = obj.BS_camera_setConsistentlyChannelName;
                    if isOn
                        targetLikelyDeg = obj.BS_camera_likelyOn_PositionDeg;
                        commandDeg = obj.BS_camera_on_PositionDeg;
                    else
                        targetLikelyDeg = obj.BS_camera_likelyOff_PositionDeg;
                        commandDeg = obj.BS_camera_off_PositionDeg;
                    end
                case "led"
                    positionChannelName = obj.BS_LED_positionChannelName;
                    setConsistentChannelName = obj.BS_LED_setConsistentlyChannelName;
                    if isOn
                        targetLikelyDeg = obj.BS_LED_likelyOn_PositionDeg;
                        commandDeg = obj.BS_LED_on_PositionDeg;
                    else
                        targetLikelyDeg = obj.BS_LED_likelyOff_PositionDeg;
                        commandDeg = obj.BS_LED_off_PositionDeg;
                    end
            end

            if ~isfinite(targetLikelyDeg)
                error("virtualInstrument_attodryAutofocus:BeamSplitterEndpointsMissing", ...
                    "Call characterizeBeamSplitterEndpoints() before setBeamSplitterState().");
            end

            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSet(setConsistentChannelName, 1);

            for attemptIndex = 1:obj.bsSetMaxAttempts
                masterRackProxy.rackSet(positionChannelName, commandDeg);
                measuredDeg = masterRackProxy.rackGet(positionChannelName);
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
                "offsetFitRoi_px", obj.offsetFitRoi_px, ...
                "cameraBsLikelyOnDeg", obj.BS_camera_likelyOn_PositionDeg, ...
                "cameraBsLikelyOffDeg", obj.BS_camera_likelyOff_PositionDeg, ...
                "ledBsLikelyOnDeg", obj.BS_LED_likelyOn_PositionDeg, ...
                "ledBsLikelyOffDeg", obj.BS_LED_likelyOff_PositionDeg);
        end

        function roi_px = selectOffsetFitRoi(obj)
            if isempty(obj.referenceSampleImage)
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before selecting offset fit ROI.");
            end
            if exist("drawrectangle", "file") ~= 2
                error("virtualInstrument_attodryAutofocus:MissingRoiTool", ...
                    "selectOffsetFitRoi requires drawrectangle.");
            end

            imageSize = size(obj.referenceSampleImage);
            if all(isfinite(obj.offsetFitRoi_px))
                initialPosition = obj.offsetFitRoi_px;
                obj.getOffsetFitRoiIndices(imageSize);
            else
                marginX = floor(0.1 * imageSize(2));
                marginY = floor(0.1 * imageSize(1));
                initialPosition = [1 + marginX, 1 + marginY, imageSize(2) - 2 * marginX, imageSize(1) - 2 * marginY];
            end

            fig = figure(Name = "Attodry Autofocus Offset ROI", NumberTitle = "off", Color = "w");
            ax = axes(fig);
            imagesc(ax, obj.referenceSampleImage);
            colormap(ax, gray(256));
            axis(ax, "image");
            ax.YDir = "normal";
            roiHandle = drawrectangle(ax, Position = initialPosition);
            wait(roiHandle);
            if ~isvalid(roiHandle)
                error("virtualInstrument_attodryAutofocus:RoiSelectionCanceled", ...
                    "Offset fit ROI selection was canceled.");
            end

            roi_px = roiHandle.Position;
            obj.offsetFitRoi_px = roi_px;
            obj.getOffsetFitRoiIndices(imageSize);
            obj.buildReferenceFitModel();
            if isvalid(fig)
                close(fig);
            end
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
            [fitRows, fitCols] = obj.getOffsetFitRoiIndices([rows, cols]);
            [xGrid, yGrid] = ndgrid(fitRows, fitCols);
            zGrid = filtered(fitRows, fitCols);

            xTrim = ceil(obj.shiftFitTrimRatio(1) / 2 * numel(fitRows));
            yTrim = ceil(obj.shiftFitTrimRatio(2) / 2 * numel(fitCols));
            if xTrim * 2 >= numel(fitRows) || yTrim * 2 >= numel(fitCols)
                error("virtualInstrument_attodryAutofocus:TrimTooLarge", ...
                    "shiftFitTrimRatio trims away the full offset fit ROI.");
            end
            rowKeep = xTrim+1:numel(fitRows)-xTrim;
            colKeep = yTrim+1:numel(fitCols)-yTrim;
            xGridTrimmed = xGrid(rowKeep, colKeep);
            yGridTrimmed = yGrid(rowKeep, colKeep);
            zGridTrimmed = zGrid(rowKeep, colKeep);

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
            result = struct("didApplyCorrection", false, "correctionKind", "none", ...
                "correctionStepsMax", 0, "dx_px", NaN, "dy_px", NaN);

            if isempty(obj.referenceSampleImage)
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before performAutofocusAndAutoshift().");
            end

            if ~obj.anc300Configured()
                liveImage = obj.acquireCameraImage();
                [dx, dy] = obj.estimateSampleOffset(liveImage);
                obj.lastEstimatedOffset_px = [dx; dy];
                result.dx_px = dx;
                result.dy_px = dy;
                return;
            end

            if obj.nextCorrectionKind == "xy"
                result.correctionKind = "xy";
                liveImage = obj.acquireCameraImage();
                [dx, dy] = obj.estimateSampleOffset(liveImage);
                obj.lastEstimatedOffset_px = [dx; dy];
                result.dx_px = dx;
                result.dy_px = dy;
                [nStepX, nStepY] = obj.runAutoshift(dx, dy);
                result.correctionStepsMax = max(abs([nStepX, nStepY]));
                obj.nextCorrectionKind = "z";
            else
                result.correctionKind = "z";
                result.correctionStepsMax = abs(obj.runZAutofocus());
                obj.nextCorrectionKind = "xy";
            end
            result.didApplyCorrection = result.correctionStepsMax >= 1;
        end
    end

    methods (Access = ?instrumentInterface)
        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    currentTB = obj.getCurrentTB();
                    getValues = currentTB(1);
                case 2
                    currentTB = obj.getCurrentTB();
                    getValues = currentTB(2);
                case 3
                    getValues = obj.colorStored;
                otherwise
                    error("virtualInstrument_attodryAutofocus:UnsupportedReadChannel", ...
                        "Unsupported read channel index %d.", channelIndex);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    obj.targetT = setValues(1);
                    obj.waitForTargetsWithCompensation();
                case 2
                    obj.targetB = setValues(1);
                    obj.waitForTargetsWithCompensation();
                case 3
                    c = setValues(1);
                    if c ~= 0 && c ~= 1
                        error("virtualInstrument_attodryAutofocus:InvalidColor", ...
                            "color must be 0 (red) or 1 (green).");
                    end
                    obj.colorStored = c;
                otherwise
                    setWriteChannelHelper@virtualInstrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            switch channelIndex
                case 1
                    currentTB = obj.getCurrentTB();
                    TF = abs(currentTB(1) - obj.targetT) <= obj.tbTargetTolerance(1);
                case 2
                    currentTB = obj.getCurrentTB();
                    TF = abs(currentTB(2) - obj.targetB) <= obj.tbTargetTolerance(2);
                case 3
                    TF = true;
                otherwise
                    TF = true;
            end
        end
    end

    methods (Access = private)
        function waitForTargetsWithCompensation(obj)
            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSetWrite([obj.T_channelName; obj.B_channelName], [obj.targetT; obj.targetB]);

            deadline = datetime("now") + obj.targetWaitTimeout;
            noCorrectionStart = NaT;
            quietAxes = [false; false];  % [xy; z]
            sampleCapacity = max(3, ceil(seconds(obj.temperatureStableWindow) / max(seconds(obj.compensationInterval), 1)) + 2);
            temperatureTimes = NaT(sampleCapacity, 1);
            temperatureSamples_K = NaN(sampleCapacity, 1);
            temperatureSampleCount = 0;
            while true
                nowTime = datetime("now");
                currentTB = obj.getCurrentTB();
                currentTemperatureTimes = temperatureTimes(1:temperatureSampleCount);
                currentTemperatureSamples_K = temperatureSamples_K(1:temperatureSampleCount);
                keepSamples = currentTemperatureTimes >= nowTime - obj.temperatureStableWindow;
                temperatureSampleCount = nnz(keepSamples);
                temperatureTimes(1:temperatureSampleCount) = currentTemperatureTimes(keepSamples);
                temperatureSamples_K(1:temperatureSampleCount) = currentTemperatureSamples_K(keepSamples);
                if temperatureSampleCount == sampleCapacity
                    temperatureTimes(1:end-1) = temperatureTimes(2:end);
                    temperatureSamples_K(1:end-1) = temperatureSamples_K(2:end);
                    temperatureSampleCount = sampleCapacity - 1;
                end
                temperatureSampleCount = temperatureSampleCount + 1;
                temperatureTimes(temperatureSampleCount) = nowTime;
                temperatureSamples_K(temperatureSampleCount) = currentTB(1);

                correction = obj.performAutofocusAndAutoshift();
                targetsSettled = obj.targetsReached(currentTB) ...
                    && obj.temperatureIsStable(temperatureTimes(1:temperatureSampleCount), temperatureSamples_K(1:temperatureSampleCount));
                if targetsSettled && ~correction.didApplyCorrection
                    if correction.correctionKind == "xy"
                        quietAxes(1) = true;
                    elseif correction.correctionKind == "z"
                        quietAxes(2) = true;
                    else
                        quietAxes(:) = true;
                    end
                    if all(quietAxes)
                        if isnat(noCorrectionStart)
                            noCorrectionStart = nowTime;
                        elseif nowTime - noCorrectionStart >= obj.noCorrectionQuietDuration
                            return;
                        end
                    end
                else
                    noCorrectionStart = NaT;
                    quietAxes(:) = false;
                end

                if nowTime >= deadline
                    error("virtualInstrument_attodryAutofocus:TargetTimeout", ...
                        "Timed out waiting for T/B targets. Target=[%.6g, %.6g], current=[%.6g, %.6g].", ...
                        obj.targetT, obj.targetB, currentTB(1), currentTB(2));
                end

                if obj.compensationInterval > seconds(0)
                    pause(seconds(obj.compensationInterval));
                end
            end
        end

        function TF = temperatureIsStable(obj, temperatureTimes, temperatureSamples_K)
            if obj.temperatureStableWindow <= seconds(0)
                TF = true;
                return;
            end
            if numel(temperatureSamples_K) < 3 || temperatureTimes(end) - temperatureTimes(1) < obj.temperatureStableWindow
                TF = false;
                return;
            end

            filterWindow = max(3, ceil(0.1 * numel(temperatureSamples_K)));
            filteredT = movmedian(temperatureSamples_K, filterWindow);
            elapsedMinutes = minutes(temperatureTimes - temperatureTimes(1));
            fitCoefficients = polyfit(elapsedMinutes, filteredT, 1);
            TF = abs(fitCoefficients(1)) < obj.temperatureStableSlopeTolerance_K_per_min;
        end

        function TF = targetsReached(obj, currentTB)
            TF = abs(currentTB(1) - obj.targetT) <= obj.tbTargetTolerance(1) ...
                && abs(currentTB(2) - obj.targetB) <= obj.tbTargetTolerance(2);
        end

        function currentTB = getCurrentTB(obj)
            masterRackProxy = obj.getMasterRackProxy();
            currentTB = masterRackProxy.rackGet([obj.T_channelName; obj.B_channelName]);
            currentTB = currentTB(:);
            if numel(currentTB) ~= 2
                error("virtualInstrument_attodryAutofocus:UnexpectedTBReadLength", ...
                    "Expected 2 values from [T, B] read channels.");
            end
        end

        function TF = anc300Configured(obj)
            TF = strlength(obj.ANC300InstrumentFriendlyName) > 0 ...
                && strlength(obj.ANC300_voltage_x_ChannelName) > 0 ...
                && strlength(obj.ANC300_voltage_y_ChannelName) > 0 ...
                && strlength(obj.ANC300_voltage_z_ChannelName) > 0;
        end

        function anc = getANC300Handle(obj)
            masterRackProxy = obj.getMasterRackProxy();
            anc = masterRackProxy.getReviewedInstrumentHandleForNonChannelMethod( ...
                obj.ANC300InstrumentFriendlyName, "instrument_ANC300", "autofocus ANC300 stepAxis");
        end

        function s = tenengradSharpness(~, image2D)
            img = double(image2D);
            gx = [-1 0 1; -2 0 2; -1 0 1];
            gy = gx.';
            Gx = conv2(img, gx, "same");
            Gy = conv2(img, gy, "same");
            s = sum(Gx(:).^2 + Gy(:).^2);
        end

        function nStepApplied = runZAutofocus(obj)
            masterRackProxy = obj.getMasterRackProxy();
            anc = obj.getANC300Handle();
            [firstTryVoltages, currentTemperature_K] = obj.getInitialPositionerVoltages();
            vz = firstTryVoltages(2);

            refSharp = obj.tenengradSharpness(obj.referenceSampleImage);
            thresh = obj.tenengradThreshold * refSharp;
            if thresh <= 0
                thresh = 1e-4;
            end

            vZ = vz;
            for nTrial = 1:obj.zStepTrialCount
                while true
                    masterRackProxy.rackSetWrite(obj.ANC300_voltage_z_ChannelName, vZ);
                    img0 = obj.acquireCameraImage();
                    s0 = obj.tenengradSharpness(img0);
                    anc.stepAxis("z", nTrial);
                    imgPlus = obj.acquireCameraImage();
                    sPlus = obj.tenengradSharpness(imgPlus);
                    anc.stepAxis("z", -2 * nTrial);
                    imgMinus = obj.acquireCameraImage();
                    sMinus = obj.tenengradSharpness(imgMinus);
                    anc.stepAxis("z", nTrial);
                    if max(abs([sPlus - s0, sMinus - s0])) < thresh
                        if vZ >= 60
                            break;
                        end
                        vZ = min(60, vZ * obj.zVoltageIncrementFactor);
                        continue;
                    end

                    stepPositions = [-nTrial; 0; nTrial];
                    sharpnessSamples = [sMinus; s0; sPlus];
                    quadraticCoefficients = polyfit(stepPositions, sharpnessSamples, 2);
                    if quadraticCoefficients(1) < 0
                        nStepApplied = round(-quadraticCoefficients(2) / (2 * quadraticCoefficients(1)));
                        nStepApplied = max(min(nStepApplied, nTrial), -nTrial);
                    else
                        [~, bestIndex] = max(sharpnessSamples);
                        nStepApplied = stepPositions(bestIndex);
                    end
                    if abs(nStepApplied) >= 1
                        anc.stepAxis("z", nStepApplied);
                    end
                    obj.updatePositionerVoltageProfile("z_voltage_V", currentTemperature_K, vZ);
                    return;
                end
            end
            error("virtualInstrument_attodryAutofocus:ZFocusResponseMissing", ...
                "Z sweeps up to %d steps did not change Tenengrad by at least %.6g at %.6g V.", ...
                obj.zStepTrialCount, thresh, vZ);
        end

        function [nStepX, nStepY] = runAutoshift(obj, dx_px, dy_px)
            if ~isfinite(dx_px) || ~isfinite(dy_px)
                error("virtualInstrument_attodryAutofocus:InvalidEstimatedOffset", ...
                    "Estimated sample offset must be finite before autoshift.");
            end
            anc = obj.getANC300Handle();
            xyMatrix = obj.calibrateXYPixelPerStepMatrix();
            correctionSteps = round(-obj.autoshiftStepRatio * (xyMatrix \ [dx_px; dy_px]));
            if any(~isfinite(correctionSteps))
                error("virtualInstrument_attodryAutofocus:InvalidXYCorrection", ...
                    "Computed XY correction steps must be finite.");
            end
            nStepX = correctionSteps(1);
            nStepY = correctionSteps(2);
            if nStepX ~= 0
                nStepX = sign(nStepX) * min(abs(nStepX), 1000);
                anc.stepAxis("x", nStepX);
            end
            if nStepY ~= 0
                nStepY = sign(nStepY) * min(abs(nStepY), 1000);
                anc.stepAxis("y", nStepY);
            end
        end

        function xyPixelPerStepMatrix = calibrateXYPixelPerStepMatrix(obj)
            obj.xyPixelPerStepMatrix = NaN(2, 2);
            masterRackProxy = obj.getMasterRackProxy();
            anc = obj.getANC300Handle();
            verifyPx = obj.cameraVerifiableStepSizePixel;
            [firstTryVoltages, currentTemperature_K] = obj.getInitialPositionerVoltages();
            axes = ["x"; "y"];
            voltageChannels = [obj.ANC300_voltage_x_ChannelName; obj.ANC300_voltage_y_ChannelName];
            xyPixelPerStepMatrix = NaN(2, 2);
            finalVoltages = NaN(2, 1);
            for axisIndex = 1:2
                voltage = firstTryVoltages(1);
                while true
                    masterRackProxy.rackSetWrite(voltageChannels(axisIndex), voltage);
                    [dx0, dy0] = obj.estimateSampleOffset(obj.acquireCameraImage());
                    offset0 = [dx0; dy0];
                    for nSteps = 1:obj.maxAutoshiftCalibrationSteps
                        anc.stepAxis(axes(axisIndex), nSteps);
                        [dx1, dy1] = obj.estimateSampleOffset(obj.acquireCameraImage());
                        anc.stepAxis(axes(axisIndex), -nSteps);
                        dPx = [dx1; dy1] - offset0;
                        dPxNorm = norm(dPx);
                        if nSteps == 1 && dPxNorm > 2 * verifyPx && voltage > 1
                            voltage = max(1, voltage / obj.zVoltageIncrementFactor);
                            break;
                        end
                        if dPxNorm >= verifyPx * 0.5
                            xyPixelPerStepMatrix(:, axisIndex) = dPx / nSteps;
                            finalVoltages(axisIndex) = voltage;
                            break;
                        end
                    end
                    if all(isfinite(xyPixelPerStepMatrix(:, axisIndex))) || voltage <= 1
                        break;
                    end
                    if nSteps == obj.maxAutoshiftCalibrationSteps
                        if voltage >= 60
                            break;
                        end
                        voltage = min(60, voltage * obj.zVoltageIncrementFactor);
                    end
                end
            end
            if any(~isfinite(xyPixelPerStepMatrix(:, 1)))
                error("virtualInstrument_attodryAutofocus:XAutoshiftCalibrationFailed", ...
                    "X calibration could not produce a camera-verifiable shift within %d steps.", obj.maxAutoshiftCalibrationSteps);
            end
            if any(~isfinite(xyPixelPerStepMatrix(:, 2)))
                error("virtualInstrument_attodryAutofocus:YAutoshiftCalibrationFailed", ...
                    "Y calibration could not produce a camera-verifiable shift within %d steps.", obj.maxAutoshiftCalibrationSteps);
            end
            matrixRcond = rcond(xyPixelPerStepMatrix);
            if matrixRcond < obj.xyResponseMatrixMinRcond
                error("virtualInstrument_attodryAutofocus:IllConditionedXYResponseMatrix", ...
                    "XY pixel-per-step matrix is ill-conditioned: rcond %.6g < %.6g.", ...
                    matrixRcond, obj.xyResponseMatrixMinRcond);
            end
            obj.xyPixelPerStepMatrix = xyPixelPerStepMatrix;
            obj.updatePositionerVoltageProfile("xy_voltage_V", currentTemperature_K, max(finalVoltages));
        end

        function [firstTryVoltages, currentTemperature_K] = getInitialPositionerVoltages(obj)
            profile = obj.readPositionerVoltageProfile();
            currentTB = obj.getCurrentTB();
            currentTemperature_K = currentTB(1);
            obj.assertVoltageProfileCoversTemperature(profile, currentTemperature_K);
            firstTryVoltages = [ ...
                interp1(profile.temperature_K, profile.xy_voltage_V, currentTemperature_K, "linear"); ...
                interp1(profile.temperature_K, profile.z_voltage_V, currentTemperature_K, "linear")];
        end

        function updatePositionerVoltageProfile(obj, voltageColumnName, currentTemperature_K, newVoltage_V)
            if ~isfinite(newVoltage_V) || newVoltage_V < 0 || newVoltage_V > 60
                error("virtualInstrument_attodryAutofocus:InvalidVoltageProfileUpdate", ...
                    "Learned positioner voltage must be finite and within [0, 60] V.");
            end
            profile = obj.readPositionerVoltageProfile();
            obj.assertVoltageProfileCoversTemperature(profile, currentTemperature_K);
            oldVoltage_V = interp1(profile.temperature_K, profile.(voltageColumnName), currentTemperature_K, "linear");
            if abs(newVoltage_V - oldVoltage_V) <= obj.voltageProfileUpdateFractionThreshold * max(abs(oldVoltage_V), eps)
                return;
            end

            newRow = table(currentTemperature_K, ...
                interp1(profile.temperature_K, profile.xy_voltage_V, currentTemperature_K, "linear"), ...
                interp1(profile.temperature_K, profile.z_voltage_V, currentTemperature_K, "linear"), ...
                VariableNames = ["temperature_K", "xy_voltage_V", "z_voltage_V"]);
            newRow.(voltageColumnName) = newVoltage_V;
            nearMask = abs(profile.temperature_K - currentTemperature_K) <= obj.voltageProfileMinTemperatureSpacing_K;
            profile(nearMask, :) = [];
            profile = sortrows([profile; newRow], "temperature_K");
            try
                writetable(profile, obj.positionerVoltageProfileCsvPath);
            catch err
                error("virtualInstrument_attodryAutofocus:VoltageProfileWriteFailed", ...
                    "Failed to update positioner voltage profile CSV: %s", err.message);
            end
        end

        function profile = readPositionerVoltageProfile(obj)
            csvPath = obj.positionerVoltageProfileCsvPath;
            if strlength(csvPath) == 0 || ~isfile(csvPath)
                error("virtualInstrument_attodryAutofocus:MissingVoltageProfileCsv", ...
                    "Positioner voltage profile CSV does not exist: %s", csvPath);
            end
            profile = readtable(csvPath);
            requiredVariables = ["temperature_K", "xy_voltage_V", "z_voltage_V"];
            if ~all(ismember(requiredVariables, string(profile.Properties.VariableNames)))
                error("virtualInstrument_attodryAutofocus:InvalidVoltageProfileCsv", ...
                    "Voltage profile CSV must contain columns: %s", strjoin(requiredVariables, ", "));
            end
            profile = profile(:, requiredVariables);
            if any(~isfinite(profile.temperature_K)) || any(~isfinite(profile.xy_voltage_V)) || any(~isfinite(profile.z_voltage_V))
                error("virtualInstrument_attodryAutofocus:InvalidVoltageProfileCsv", ...
                    "Voltage profile temperatures and voltages must be finite.");
            end
            if any(profile.xy_voltage_V < 0 | profile.xy_voltage_V > 60 | profile.z_voltage_V < 0 | profile.z_voltage_V > 60)
                error("virtualInstrument_attodryAutofocus:InvalidVoltageProfileCsv", ...
                    "Voltage profile voltages must be within [0, 60] V.");
            end
            profile = sortrows(profile, "temperature_K");
            if any(diff(profile.temperature_K) <= 0)
                error("virtualInstrument_attodryAutofocus:InvalidVoltageProfileCsv", ...
                    "Voltage profile temperatures must be unique.");
            end
        end

        function assertVoltageProfileCoversTemperature(~, profile, currentTemperature_K)
            if currentTemperature_K < profile.temperature_K(1) || currentTemperature_K > profile.temperature_K(end)
                error("virtualInstrument_attodryAutofocus:VoltageProfileTemperatureOutOfRange", ...
                    "Current temperature %.6g K is outside voltage profile range [%.6g, %.6g] K.", ...
                    currentTemperature_K, profile.temperature_K(1), profile.temperature_K(end));
            end
        end

        function setLaserPathState(obj, NameValueArgs)
            arguments
                obj
                NameValueArgs.blocked (1, 1) logical
                NameValueArgs.ndOn (1, 1) logical
            end

            if obj.colorStored == 0
                blockChannel = obj.block_red_positionChannelName;
                NDChannel = obj.ND_red_positionChannelName;
                blockTargetDeg = obj.block_red_unblocked_PositionDeg;
                ndTargetDeg = obj.ND_red_off_PositionDeg;
                if NameValueArgs.blocked
                    blockTargetDeg = obj.block_red_blocked_PositionDeg;
                end
                if NameValueArgs.ndOn
                    ndTargetDeg = obj.ND_red_on_PositionDeg;
                end
            else
                blockChannel = obj.block_green_positionChannelName;
                NDChannel = obj.ND_green_positionChannelName;
                blockTargetDeg = obj.block_green_unblocked_PositionDeg;
                ndTargetDeg = obj.ND_green_off_PositionDeg;
                if NameValueArgs.blocked
                    blockTargetDeg = obj.block_green_blocked_PositionDeg;
                end
                if NameValueArgs.ndOn
                    ndTargetDeg = obj.ND_green_on_PositionDeg;
                end
            end

            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSet([blockChannel; NDChannel], [blockTargetDeg; ndTargetDeg]);
        end

        function setLedState(obj, ledOn)
            if ledOn
                if obj.colorStored == 0
                    rgb = [1; 0; 0];  % red
                else
                    rgb = [0; 1; 0];  % green
                end
            else
                rgb = [0; 0; 0];
            end

            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSet(obj.ledRgbChannelName, rgb);
        end

        function [likelyOnDeg, likelyOffDeg] = measureLikelyEndpoints(obj, positionChannelName, onCommandDeg, offCommandDeg)
            masterRackProxy = obj.getMasterRackProxy();

            onSamples = zeros(obj.bsCalibrationCycles, 1);
            offSamples = zeros(obj.bsCalibrationCycles, 1);

            for cycleIndex = 1:obj.bsCalibrationCycles
                masterRackProxy.rackSet(positionChannelName, offCommandDeg);
                offSamples(cycleIndex) = masterRackProxy.rackGet(positionChannelName);

                masterRackProxy.rackSet(positionChannelName, onCommandDeg);
                onSamples(cycleIndex) = masterRackProxy.rackGet(positionChannelName);
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
            masterRackProxy = obj.getMasterRackProxy();
            cameraHandle = masterRackProxy.getReviewedInstrumentHandleForNonChannelMethod( ...
                obj.cameraInstrumentFriendlyName, "", "autofocus camera acquireSingleImage");
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
            [fitRows, fitCols] = obj.getOffsetFitRoiIndices([rows, cols]);

            xTrim = ceil(obj.shiftFitTrimRatio(1) / 2 * numel(fitRows));
            yTrim = ceil(obj.shiftFitTrimRatio(2) / 2 * numel(fitCols));
            if xTrim * 2 >= numel(fitRows) || yTrim * 2 >= numel(fitCols)
                error("virtualInstrument_attodryAutofocus:TrimTooLarge", ...
                    "shiftFitTrimRatio trims away the full offset fit ROI.");
            end

            [xGrid, yGrid] = ndgrid(1:rows, 1:cols);
            obj.referenceSampleInterpolant = griddedInterpolant(xGrid, yGrid, referenceFiltered, "spline", "none");
            obj.referenceShiftFitModel = @(dx, dy, x, y) obj.referenceSampleInterpolant(x + dx, y + dy);
            obj.referenceFitSize_px = [rows, cols];
            obj.referenceFitTrim_px = [xTrim, yTrim];
        end

        function [fitRows, fitCols] = getOffsetFitRoiIndices(obj, imageSize)
            rows = imageSize(1);
            cols = imageSize(2);
            roi = obj.offsetFitRoi_px;
            if all(isnan(roi))
                fitRows = 1:rows;
                fitCols = 1:cols;
                return;
            end
            if any(isnan(roi)) || any(~isfinite(roi)) || roi(3) <= 0 || roi(4) <= 0
                error("virtualInstrument_attodryAutofocus:InvalidOffsetFitRoi", ...
                    "offsetFitRoi_px must be [x, y, width, height] with finite positive width and height, or all NaN.");
            end

            x1 = round(roi(1));
            y1 = round(roi(2));
            x2 = round(roi(1) + roi(3) - 1);
            y2 = round(roi(2) + roi(4) - 1);
            if x1 < 1 || y1 < 1 || x2 > cols || y2 > rows || x2 < x1 || y2 < y1
                error("virtualInstrument_attodryAutofocus:OffsetFitRoiOutOfBounds", ...
                    "offsetFitRoi_px must lie inside image bounds [height=%d, width=%d].", rows, cols);
            end
            fitRows = y1:y2;
            fitCols = x1:x2;
        end

        function assertReferenceFitReady(obj)
            if isempty(obj.referenceSampleImage) || isempty(obj.referenceShiftFitModel)
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before estimating sample offsets.");
            end
        end

        function assertChannelsExist(obj, channelNames)
            channelNames = unique(channelNames(:));
            obj.getMasterRackProxy().assertChannelsExist(channelNames);
        end

        function assertOpticsChannelsConfigured(obj)
            labels = [ ...
                "block_red_positionChannelName"; ...
                "block_green_positionChannelName"; ...
                "ND_red_positionChannelName"; ...
                "ND_green_positionChannelName"; ...
                "BS_camera_positionChannelName"; ...
                "BS_LED_positionChannelName"; ...
                "BS_camera_setConsistentlyChannelName"; ...
                "BS_LED_setConsistentlyChannelName"; ...
                "ledRgbChannelName"];

            values = [ ...
                obj.block_red_positionChannelName; ...
                obj.block_green_positionChannelName; ...
                obj.ND_red_positionChannelName; ...
                obj.ND_green_positionChannelName; ...
                obj.BS_camera_positionChannelName; ...
                obj.BS_LED_positionChannelName; ...
                obj.BS_camera_setConsistentlyChannelName; ...
                obj.BS_LED_setConsistentlyChannelName; ...
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
