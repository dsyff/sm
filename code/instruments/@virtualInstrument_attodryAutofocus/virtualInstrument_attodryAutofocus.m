classdef virtualInstrument_attodryAutofocus < virtualInstrumentInterface
    % Virtual instrument for Attodry T/B control with laser-referenced autofocus/autoshift.
    %
    % Coordinate convention:
    %   - Beamspot coordinates are stored as [x; y] = [column; row] in camera pixels.
    %   - Sample-offset fit coordinates are stored as [rowShift; columnShift], matching
    %     estimateSampleOffset() and the existing XY response matrix calibration.
    %
    % The sample reference is never automatically updated during autofocus. Live XY
    % compensation uses the original sample reference plus the live laser beamspot
    % displacement from the original reference beamspot.

    properties
        T_channelName (1, 1) string
        B_channelName (1, 1) string

        cameraInstrumentFriendlyName (1, 1) string = "CS165MU"
        cameraColorChannelName (1, 1) string = ""

        block_red_positionChannelName (1, 1) string = ""
        block_green_positionChannelName (1, 1) string = ""
        ND_red_positionChannelName (1, 1) string = ""
        ND_green_positionChannelName (1, 1) string = ""
        BS_camera_positionChannelName (1, 1) string = ""
        BS_LED_positionChannelName (1, 1) string = ""
        BS_camera_setConsistentlyChannelName (1, 1) string = ""
        BS_LED_setConsistentlyChannelName (1, 1) string = ""
        LEDRGBChannelName (1, 1) string = ""

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
        cooldownWaitTimeout (1, 1) duration = hours(24)
        diagnosticOutputFolder (1, 1) string = ""
        diagnosticInterval (1, 1) duration = minutes(5)
        diagnosticCrosshairArm_px (1, 1) double {mustBeInteger, mustBePositive} = 28
        diagnosticCrosshairGap_px (1, 1) double {mustBeInteger, mustBeNonnegative} = 6
        diagnosticCrosshairLineWidth_px (1, 1) double {mustBeInteger, mustBePositive} = 2

        bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
        bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
        bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.3
        % Binning step (deg) in pickLikelyPosition when finding BS endpoint from repeated reads. Default = 1 tick (4096 ticks/360°).
        bsQuantizationDeg (1, 1) double {mustBePositive} = 360 / 4096

        shiftFitTrimRatio (2, 1) double = [0.3; 0.3]
        offsetFitRoi_px (1, 4) double = [NaN, NaN, NaN, NaN]  % [x, y, width, height]
        sampleOffsetEstimatorMode (1, 1) string = "spline_shift"

        % Beamspot circular center-of-mass settings.
        beamspotCircleRadius_px (1, 1) double = NaN             % NaN => 0.45 * min(image width, image height)
        beamspotBackgroundPercentile (1, 1) double = 20
        beamspotWeightPower (1, 1) double = 1
        beamspotCenterIterations (1, 1) double {mustBeInteger, mustBePositive} = 5
        beamspotCenterTolerance_px (1, 1) double {mustBePositive} = 0.01

        % After successful autofocus during a T/B ramp, restore the optics state expected by measurements.
        turnBeamSplittersOffAfterAutofocus (1, 1) logical = true

        % ANC300 nanopositioner (optional). Empty = no autofocus/autoshift actuation.
        attoDRYInstrumentFriendlyName (1, 1) string = "attoDRY2100"
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
        zVoltageIncrementFactor (1, 1) double {mustBePositive} = 1.05
        zStepTrialCount (1, 1) double {mustBeInteger, mustBePositive} = 5

        targetStepSizePixel (1, 1) double {mustBePositive} = 1.0
        xyCalibrationTargetDisplacement_px (1, 1) double {mustBePositive} = 2.0
        xyCalibrationInitialVoltageScale (1, 1) double {mustBePositive} = 1.0
        xyCalibrationMaxVoltageFactor (1, 1) double {mustBeGreaterThanOrEqual(xyCalibrationMaxVoltageFactor, 1)} = 1.5
        xyCalibrationOscillationCycles (1, 1) double {mustBeInteger, mustBePositive} = 10
        xyCalibrationStepSizeToleranceFraction (1, 1) double {mustBeNonnegative} = 0.20
        xyCalibrationMinFitRsquare (1, 1) double {mustBeGreaterThanOrEqual(xyCalibrationMinFitRsquare, 0), mustBeLessThanOrEqual(xyCalibrationMinFitRsquare, 1)} = 0.90
        autoshiftStepRatio (1, 1) double {mustBePositive} = 0.5
        xyResponseMatrixMinRcond (1, 1) double {mustBePositive} = 1e-3
        maxAutoshiftCalibrationSteps (1, 1) double {mustBeInteger, mustBePositive} = 20
        xyCalibrationStepIncrement (1, 1) double {mustBeInteger, mustBePositive} = 1
        xyCalibrationMinSlopeRsquare (1, 1) double {mustBeGreaterThanOrEqual(xyCalibrationMinSlopeRsquare, 0), mustBeLessThanOrEqual(xyCalibrationMinSlopeRsquare, 1)} = 0.70
        xyCalibrationMaxResidual_px (1, 1) double {mustBePositive} = 1.0
        xyCalibrationReturnTolerance_px (1, 1) double {mustBePositive} = 1.0
        maxAutoshiftCorrectionStepsPerAxis (1, 1) double {mustBeInteger, mustBePositive} = 5
    end

    properties (SetAccess = private)
        targetT (1, 1) double = NaN
        targetB (1, 1) double = NaN
        colorStored (1, 1) double = 0  % 0 = red, 1 = green

        referenceSampleImage
        referenceLaserOnSampleImage
        referenceLaserOnlyImage
        referenceBeamspot_px (2, 1) double = [NaN; NaN]  % [x; y] = [column; row]

        lastBeamspot_px (2, 1) double = [NaN; NaN]        % [x; y] = [column; row]
        lastBeamspotDelta_px (2, 1) double = [NaN; NaN]   % live - reference, [x; y]
        lastRawSampleOffset_px (2, 1) double = [NaN; NaN] % [rowShift; columnShift]
        lastBeamReferencedOffset_px (2, 1) double = [NaN; NaN]
        lastEstimatedOffset_px (2, 1) double = [0; 0]     % compatibility alias for beam-referenced offset
    end

    properties (Access = private)
        BS_camera_likelyOn_PositionDeg (1, 1) double = NaN
        BS_camera_likelyOff_PositionDeg (1, 1) double = NaN
        BS_LED_likelyOn_PositionDeg (1, 1) double = NaN
        BS_LED_likelyOff_PositionDeg (1, 1) double = NaN

        referenceFilteredImage
        referenceFitSize_px (1, 2) double = [NaN, NaN]
        referenceFitTrim_px (1, 2) double = [NaN, NaN]

        xyPixelPerStepMatrix (2, 2) double = NaN(2, 2)
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
                NameValueArgs.cameraColorChannelName (1, 1) string = ""

                NameValueArgs.block_red_positionChannelName (1, 1) string = ""
                NameValueArgs.block_green_positionChannelName (1, 1) string = ""
                NameValueArgs.ND_red_positionChannelName (1, 1) string = ""
                NameValueArgs.ND_green_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_camera_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_LED_positionChannelName (1, 1) string = ""
                NameValueArgs.BS_camera_setConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.BS_LED_setConsistentlyChannelName (1, 1) string = ""
                NameValueArgs.LEDRGBChannelName (1, 1) string = ""

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
                NameValueArgs.cooldownWaitTimeout (1, 1) duration = hours(24)
                NameValueArgs.diagnosticOutputFolder (1, 1) string = ""
                NameValueArgs.diagnosticInterval (1, 1) duration = minutes(5)

                NameValueArgs.bsCalibrationCycles (1, 1) double {mustBeInteger, mustBePositive} = 6
                NameValueArgs.bsSetMaxAttempts (1, 1) double {mustBeInteger, mustBePositive} = 20
                NameValueArgs.bsPositionToleranceDeg (1, 1) double {mustBePositive} = 0.3
                NameValueArgs.bsQuantizationDeg (1, 1) double {mustBePositive} = 360 / 4096

                NameValueArgs.shiftFitTrimRatio (2, 1) double = [0.3; 0.3]
                NameValueArgs.offsetFitRoi_px (1, 4) double = [NaN, NaN, NaN, NaN]
                NameValueArgs.sampleOffsetEstimatorMode (1, 1) string = "spline_shift"
                NameValueArgs.beamspotCircleRadius_px (1, 1) double = NaN
                NameValueArgs.beamspotBackgroundPercentile (1, 1) double = 20
                NameValueArgs.beamspotWeightPower (1, 1) double = 1
                NameValueArgs.beamspotCenterIterations (1, 1) double {mustBeInteger, mustBePositive} = 5
                NameValueArgs.beamspotCenterTolerance_px (1, 1) double {mustBePositive} = 0.01
                NameValueArgs.turnBeamSplittersOffAfterAutofocus (1, 1) logical = true

                NameValueArgs.attoDRYInstrumentFriendlyName (1, 1) string = "attoDRY2100"
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
                NameValueArgs.zVoltageIncrementFactor (1, 1) double {mustBePositive} = 1.05
                NameValueArgs.zStepTrialCount (1, 1) double {mustBeInteger, mustBePositive} = 5
                NameValueArgs.targetStepSizePixel (1, 1) double {mustBePositive} = 1.0
                NameValueArgs.xyCalibrationTargetDisplacement_px (1, 1) double {mustBePositive} = 2.0
                NameValueArgs.xyCalibrationInitialVoltageScale (1, 1) double {mustBePositive} = 1.0
                NameValueArgs.xyCalibrationMaxVoltageFactor (1, 1) double {mustBeGreaterThanOrEqual(NameValueArgs.xyCalibrationMaxVoltageFactor, 1)} = 1.5
                NameValueArgs.xyCalibrationOscillationCycles (1, 1) double {mustBeInteger, mustBePositive} = 10
                NameValueArgs.xyCalibrationStepSizeToleranceFraction (1, 1) double {mustBeNonnegative} = 0.20
                NameValueArgs.xyCalibrationMinFitRsquare (1, 1) double {mustBeGreaterThanOrEqual(NameValueArgs.xyCalibrationMinFitRsquare, 0), mustBeLessThanOrEqual(NameValueArgs.xyCalibrationMinFitRsquare, 1)} = 0.90
                NameValueArgs.autoshiftStepRatio (1, 1) double {mustBePositive} = 0.5
                NameValueArgs.xyResponseMatrixMinRcond (1, 1) double {mustBePositive} = 1e-3
                NameValueArgs.maxAutoshiftCalibrationSteps (1, 1) double {mustBeInteger, mustBePositive} = 20
                NameValueArgs.xyCalibrationStepIncrement (1, 1) double {mustBeInteger, mustBePositive} = 1
                NameValueArgs.xyCalibrationMinSlopeRsquare (1, 1) double {mustBeGreaterThanOrEqual(NameValueArgs.xyCalibrationMinSlopeRsquare, 0), mustBeLessThanOrEqual(NameValueArgs.xyCalibrationMinSlopeRsquare, 1)} = 0.70
                NameValueArgs.xyCalibrationMaxResidual_px (1, 1) double {mustBePositive} = 1.0
                NameValueArgs.xyCalibrationReturnTolerance_px (1, 1) double {mustBePositive} = 1.0
                NameValueArgs.maxAutoshiftCorrectionStepsPerAxis (1, 1) double {mustBeInteger, mustBePositive} = 5
            end

            obj@virtualInstrumentInterface(address, masterRackProxy);

            obj.T_channelName = NameValueArgs.T_channelName;
            obj.B_channelName = NameValueArgs.B_channelName;

            obj.cameraInstrumentFriendlyName = NameValueArgs.cameraInstrumentFriendlyName;
            obj.cameraColorChannelName = NameValueArgs.cameraColorChannelName;

            obj.block_red_positionChannelName = NameValueArgs.block_red_positionChannelName;
            obj.block_green_positionChannelName = NameValueArgs.block_green_positionChannelName;
            obj.ND_red_positionChannelName = NameValueArgs.ND_red_positionChannelName;
            obj.ND_green_positionChannelName = NameValueArgs.ND_green_positionChannelName;
            obj.BS_camera_positionChannelName = NameValueArgs.BS_camera_positionChannelName;
            obj.BS_LED_positionChannelName = NameValueArgs.BS_LED_positionChannelName;
            obj.BS_camera_setConsistentlyChannelName = NameValueArgs.BS_camera_setConsistentlyChannelName;
            obj.BS_LED_setConsistentlyChannelName = NameValueArgs.BS_LED_setConsistentlyChannelName;
            obj.LEDRGBChannelName = NameValueArgs.LEDRGBChannelName;

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
            obj.cooldownWaitTimeout = NameValueArgs.cooldownWaitTimeout;
            if obj.cooldownWaitTimeout <= seconds(0)
                error("virtualInstrument_attodryAutofocus:InvalidCooldownWaitTimeout", ...
                    "cooldownWaitTimeout must be positive.");
            end
            obj.diagnosticInterval = NameValueArgs.diagnosticInterval;
            if obj.diagnosticInterval <= seconds(0)
                error("virtualInstrument_attodryAutofocus:InvalidDiagnosticInterval", ...
                    "diagnosticInterval must be positive.");
            end

            obj.bsCalibrationCycles = NameValueArgs.bsCalibrationCycles;
            obj.bsSetMaxAttempts = NameValueArgs.bsSetMaxAttempts;
            obj.bsPositionToleranceDeg = NameValueArgs.bsPositionToleranceDeg;
            obj.bsQuantizationDeg = NameValueArgs.bsQuantizationDeg;

            if any(NameValueArgs.shiftFitTrimRatio <= 0 | NameValueArgs.shiftFitTrimRatio >= 0.6)
                error("virtualInstrument_attodryAutofocus:InvalidShiftFitTrimRatio", ...
                    "shiftFitTrimRatio values must be in (0, 0.6).");
            end
            if NameValueArgs.xyCalibrationStepSizeToleranceFraction >= 1
                error("virtualInstrument_attodryAutofocus:InvalidXYStepSizeTolerance", ...
                    "xyCalibrationStepSizeToleranceFraction must be less than 1.");
            end
            obj.shiftFitTrimRatio = NameValueArgs.shiftFitTrimRatio;
            obj.offsetFitRoi_px = NameValueArgs.offsetFitRoi_px;
            obj.sampleOffsetEstimatorMode = NameValueArgs.sampleOffsetEstimatorMode;
            if ~ismember(obj.sampleOffsetEstimatorMode, "spline_shift")
                error("virtualInstrument_attodryAutofocus:UnknownSampleOffsetEstimator", ...
                    "sampleOffsetEstimatorMode must be ""spline_shift"".");
            end

            if NameValueArgs.beamspotBackgroundPercentile < 0 || NameValueArgs.beamspotBackgroundPercentile > 100
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotBackgroundPercentile", ...
                    "beamspotBackgroundPercentile must be within [0, 100].");
            end
            if NameValueArgs.beamspotWeightPower <= 0 || ~isfinite(NameValueArgs.beamspotWeightPower)
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotWeightPower", ...
                    "beamspotWeightPower must be finite and positive.");
            end
            if isfinite(NameValueArgs.beamspotCircleRadius_px) && NameValueArgs.beamspotCircleRadius_px <= 0
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotCircleRadius", ...
                    "beamspotCircleRadius_px must be positive or NaN.");
            end
            obj.beamspotCircleRadius_px = NameValueArgs.beamspotCircleRadius_px;
            obj.beamspotBackgroundPercentile = NameValueArgs.beamspotBackgroundPercentile;
            obj.beamspotWeightPower = NameValueArgs.beamspotWeightPower;
            obj.beamspotCenterIterations = NameValueArgs.beamspotCenterIterations;
            obj.beamspotCenterTolerance_px = NameValueArgs.beamspotCenterTolerance_px;
            obj.turnBeamSplittersOffAfterAutofocus = NameValueArgs.turnBeamSplittersOffAfterAutofocus;

            obj.attoDRYInstrumentFriendlyName = NameValueArgs.attoDRYInstrumentFriendlyName;
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
            classFilePath = string(which(class(obj)));
            if strlength(classFilePath) == 0
                error("virtualInstrument_attodryAutofocus:ClassFileNotFound", ...
                    "Unable to resolve class folder with which(class(obj)).");
            end
            classFolder = string(fileparts(classFilePath));
            if strlength(NameValueArgs.positionerVoltageProfileCsvPath) == 0
                obj.positionerVoltageProfileCsvPath = fullfile(classFolder, ...
                    "attodry_autofocus_positioner_voltage_profile.csv");
            else
                obj.positionerVoltageProfileCsvPath = NameValueArgs.positionerVoltageProfileCsvPath;
            end
            if strlength(NameValueArgs.diagnosticOutputFolder) == 0
                repoRoot = string(fileparts(fileparts(fileparts(classFolder))));
                obj.diagnosticOutputFolder = fullfile(repoRoot, "temp", "attodry_autofocus_diagnostics");
            else
                obj.diagnosticOutputFolder = NameValueArgs.diagnosticOutputFolder;
            end
            obj.tenengradThreshold = NameValueArgs.tenengradThreshold;
            obj.maxAutofocusIterations = NameValueArgs.maxAutofocusIterations;
            obj.zVoltageIncrementFactor = NameValueArgs.zVoltageIncrementFactor;
            obj.zStepTrialCount = NameValueArgs.zStepTrialCount;
            obj.targetStepSizePixel = NameValueArgs.targetStepSizePixel;
            obj.xyCalibrationTargetDisplacement_px = NameValueArgs.xyCalibrationTargetDisplacement_px;
            obj.xyCalibrationInitialVoltageScale = NameValueArgs.xyCalibrationInitialVoltageScale;
            obj.xyCalibrationMaxVoltageFactor = NameValueArgs.xyCalibrationMaxVoltageFactor;
            obj.xyCalibrationOscillationCycles = NameValueArgs.xyCalibrationOscillationCycles;
            obj.xyCalibrationStepSizeToleranceFraction = NameValueArgs.xyCalibrationStepSizeToleranceFraction;
            obj.xyCalibrationMinFitRsquare = NameValueArgs.xyCalibrationMinFitRsquare;
            obj.autoshiftStepRatio = NameValueArgs.autoshiftStepRatio;
            obj.xyResponseMatrixMinRcond = NameValueArgs.xyResponseMatrixMinRcond;
            obj.maxAutoshiftCalibrationSteps = NameValueArgs.maxAutoshiftCalibrationSteps;
            obj.xyCalibrationStepIncrement = NameValueArgs.xyCalibrationStepIncrement;
            obj.xyCalibrationMinSlopeRsquare = NameValueArgs.xyCalibrationMinSlopeRsquare;
            obj.xyCalibrationMaxResidual_px = NameValueArgs.xyCalibrationMaxResidual_px;
            obj.xyCalibrationReturnTolerance_px = NameValueArgs.xyCalibrationReturnTolerance_px;
            obj.maxAutoshiftCorrectionStepsPerAxis = NameValueArgs.maxAutoshiftCorrectionStepsPerAxis;

            if strlength(obj.ANC300InstrumentFriendlyName) > 0
                obj.assertChannelsExist([obj.ANC300_voltage_x_ChannelName; obj.ANC300_voltage_y_ChannelName; obj.ANC300_voltage_z_ChannelName]);
            end

            obj.assertChannelsExist([obj.T_channelName; obj.B_channelName]);
            if strlength(obj.cameraColorChannelName) > 0
                obj.assertChannelsExist(obj.cameraColorChannelName);
            end

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
            [LEDOnDeg, LEDOffDeg] = obj.measureLikelyEndpoints( ...
                obj.BS_LED_positionChannelName, obj.BS_LED_on_PositionDeg, obj.BS_LED_off_PositionDeg);

            obj.BS_camera_likelyOn_PositionDeg = cameraOnDeg;
            obj.BS_camera_likelyOff_PositionDeg = cameraOffDeg;
            obj.BS_LED_likelyOn_PositionDeg = LEDOnDeg;
            obj.BS_LED_likelyOff_PositionDeg = LEDOffDeg;

            positions = struct( ...
                "cameraOnDeg", cameraOnDeg, ...
                "cameraOffDeg", cameraOffDeg, ...
                "LEDOnDeg", LEDOnDeg, ...
                "LEDOffDeg", LEDOffDeg);
        end

        function setBeamSplitterState(obj, beamSplitterName, isOn)
            arguments
                obj
                beamSplitterName (1, 1) string {mustBeMember(beamSplitterName, ["camera", "LED"])}
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
                case "LED"
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
            cleanup = onCleanup(@() obj.blockLaserOnly());

            % Reference sample image: camera BS on, LED BS on, laser blocked, LED on.
            obj.prepareAutofocusBeamSplitters();
            sampleImage = obj.acquireSampleImageForAutofocus();

            % Reference laser image: keep camera BS and LED BS on; turn off LED; open laser path with ND on.
            laserOnlyImage = obj.acquireLaserSpotImage();
            [referenceBeamspotPx, beamspotStats] = obj.estimateBeamspotCenterInternal(laserOnlyImage, [NaN; NaN]);

            obj.referenceSampleImage = sampleImage;
            obj.referenceLaserOnSampleImage = [];
            obj.referenceLaserOnlyImage = laserOnlyImage;
            obj.referenceBeamspot_px = referenceBeamspotPx;
            obj.lastBeamspot_px = referenceBeamspotPx;
            obj.lastBeamspotDelta_px = [0; 0];
            obj.buildReferenceFitModel();
            obj.updateCameraOffsetFitOverlay([0; 0]);

            obj.restoreMeasurementOptics();

            references = struct( ...
                "sampleImage", sampleImage, ...
                "laserOnSampleImage", [], ...
                "laserOnlyImage", laserOnlyImage, ...
                "referenceBeamspot_px", referenceBeamspotPx, ...
                "beamspotStats", beamspotStats, ...
                "offsetFitRoi_px", obj.offsetFitRoi_px, ...
                "cameraBsLikelyOnDeg", obj.BS_camera_likelyOn_PositionDeg, ...
                "cameraBsLikelyOffDeg", obj.BS_camera_likelyOff_PositionDeg, ...
                "LEDBsLikelyOnDeg", obj.BS_LED_likelyOn_PositionDeg, ...
                "LEDBsLikelyOffDeg", obj.BS_LED_likelyOff_PositionDeg);

            clear cleanup;
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

            fig = figure(Name = "Attodry Autofocus Sample-Shift ROI", NumberTitle = "off", Color = "w");
            ax = axes(fig);
            imagesc(ax, obj.referenceSampleImage);
            colormap(ax, gray(256));
            axis(ax, "image");
            ax.YDir = "reverse";
            xlabel(ax, "x pixel (horizontal)");
            ylabel(ax, "y pixel (vertical, origin top-left)");
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
            obj.updateCameraOffsetFitOverlay([0; 0]);
            if isvalid(fig)
                close(fig);
            end
        end

        function [dx, dy, gof] = estimateSampleOffset(obj, image2D, roiShift_xy)
            if nargin < 3
                roiShift_xy = [0; 0];
            end
            obj.assertReferenceFitReady();

            if ~isequal(size(image2D), obj.referenceFitSize_px)
                error("virtualInstrument_attodryAutofocus:ImageSizeMismatch", ...
                    "Expected image size [%d, %d], received [%d, %d].", ...
                    obj.referenceFitSize_px(1), obj.referenceFitSize_px(2), size(image2D, 1), size(image2D, 2));
            end

            switch obj.sampleOffsetEstimatorMode
                case "spline_shift"
                    [dx, dy, gof] = obj.estimateSampleOffsetSplineShift(image2D, roiShift_xy);
                otherwise
                    error("virtualInstrument_attodryAutofocus:UnknownSampleOffsetEstimator", ...
                        "Unknown sampleOffsetEstimatorMode ""%s"".", obj.sampleOffsetEstimatorMode);
            end
        end

        function [dx, dy, gof] = estimateSampleOffsetSplineShift(obj, image2D, roiShift_xy)
            filtered = log(double(image2D) + 1);
            [rows, cols] = size(filtered);
            [fitRows, fitCols] = obj.getOffsetFitRoiIndices([rows, cols], roiShift_xy);
            [fullRows, fullCols] = ndgrid(1:rows, 1:cols);
            currentInterpolant = griddedInterpolant(fullRows, fullCols, filtered, "spline", "none");
            [xGrid, yGrid] = ndgrid(fitRows, fitCols);
            zGrid = obj.referenceFilteredImage(fitRows, fitCols);

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

            currentShiftFitModel = @(dx, dy, x, y) currentInterpolant(x + dx, y + dy);
            [fitResult, gof] = fit([xColumn, yColumn], zColumn, currentShiftFitModel, ...
                StartPoint = [0, 0], ...
                Lower = [-xTrim, -yTrim], ...
                Upper = [xTrim, yTrim], ...
                DiffMinChange = 0.00001, ...
                TolFun = 0.001, ...
                TolX = 0.001);

            dx = fitResult.dx;
            dy = fitResult.dy;
        end

        function [center_px, stats] = estimateBeamspotCenter(obj, image2D)
            [center_px, stats] = obj.estimateBeamspotCenterInternal(image2D, [NaN; NaN]);
        end

        function cooldown(obj)
            if strlength(obj.attoDRYInstrumentFriendlyName) == 0
                error("virtualInstrument_attodryAutofocus:AttoDRYNotConfigured", ...
                    "attoDRYInstrumentFriendlyName must be configured before cooldown().");
            end
            attoDRY = obj.getMasterRackProxy().getReviewedInstrumentHandleForNonChannelMethod( ...
                obj.attoDRYInstrumentFriendlyName, "instrument_attoDRY2100", "attodry autofocus cooldown");
            attoDRY.cooldown();
            obj.waitForTargetsWithCompensation("cooldown", false, obj.cooldownWaitTimeout);
        end

        function result = performAutofocusOnly(obj)
            result = struct( ...
                "didApplyCorrection", false, ...
                "correctionKind", "z", ...
                "correctionStepsMax", 0, ...
                "zSteps", 0);

            if ~obj.anc300Configured()
                error("virtualInstrument_attodryAutofocus:ANC300NotConfigured", ...
                    "ANC300 channels must be configured before performAutofocusOnly().");
            end

            cleanup = onCleanup(@() obj.blockLaserOnly());
            obj.prepareAutofocusBeamSplitters();

            nStepZ = obj.runZAutofocus();
            result.zSteps = nStepZ;
            result.correctionStepsMax = abs(nStepZ);
            result.didApplyCorrection = result.correctionStepsMax >= 1;

            clear cleanup;
        end

        function result = performAutofocusAndAutoshift(obj)
            result = struct( ...
                "didApplyCorrection", false, ...
                "correctionKind", "cycle", ...
                "correctionStepsMax", 0, ...
                "dx_px", NaN, ...
                "dy_px", NaN, ...
                "raw_dx_px", NaN, ...
                "raw_dy_px", NaN, ...
                "beamspot_x_px", NaN, ...
                "beamspot_y_px", NaN, ...
                "beamspotDelta_x_px", NaN, ...
                "beamspotDelta_y_px", NaN, ...
                "zSteps", 0, ...
                "xySteps", [0; 0]);

            if isempty(obj.referenceSampleImage) || any(~isfinite(obj.referenceBeamspot_px))
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before performAutofocusAndAutoshift().");
            end

            cleanup = onCleanup(@() obj.blockLaserOnly());
            obj.prepareAutofocusBeamSplitters();

            if obj.anc300Configured()
                nStepZ = obj.runZAutofocus();
            else
                nStepZ = 0;
                obj.acquireSampleImageForAutofocus();
            end
            result.zSteps = nStepZ;

            [beamspotImage, beamspot_px] = obj.acquireLaserSpotImageAndCenter(); %#ok<ASGLU>
            beamDelta_px = beamspot_px - obj.referenceBeamspot_px;
            obj.lastBeamspot_px = beamspot_px;
            obj.lastBeamspotDelta_px = beamDelta_px;

            obj.updateCameraOffsetFitOverlay(beamDelta_px);
            sampleImage = obj.acquireSampleImageForAutoshift();
            [rawDx, rawDy] = obj.estimateSampleOffset(sampleImage, beamDelta_px);
            rawOffset_px = [rawDx; rawDy];
            correctedOffset_px = obj.computeBeamReferencedSampleOffset(rawOffset_px, beamspot_px);

            obj.lastRawSampleOffset_px = rawOffset_px;
            obj.lastBeamReferencedOffset_px = correctedOffset_px;
            obj.lastEstimatedOffset_px = correctedOffset_px;

            result.dx_px = correctedOffset_px(1);
            result.dy_px = correctedOffset_px(2);
            result.raw_dx_px = rawDx;
            result.raw_dy_px = rawDy;
            result.beamspot_x_px = beamspot_px(1);
            result.beamspot_y_px = beamspot_px(2);
            result.beamspotDelta_x_px = beamDelta_px(1);
            result.beamspotDelta_y_px = beamDelta_px(2);

            if obj.anc300Configured()
                [nStepX, nStepY] = obj.runAutoshift(correctedOffset_px(1), correctedOffset_px(2));
            else
                nStepX = 0;
                nStepY = 0;
            end
            result.xySteps = [nStepX; nStepY];
            result.correctionStepsMax = max(abs([nStepZ, nStepX, nStepY]));
            result.didApplyCorrection = result.correctionStepsMax >= 1;

            clear cleanup;
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
                    obj.waitForTargetsWithCompensation("setT");
                case 2
                    obj.targetB = setValues(1);
                    obj.waitForTargetsWithCompensation("setB");
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
        function waitForTargetsWithCompensation(obj, operationName, waitForTargets, waitTimeout)
            if nargin < 3
                waitForTargets = true;
            end
            if nargin < 4
                waitTimeout = obj.targetWaitTimeout;
            end
            cleanup = onCleanup(@() obj.blockLaserOnly());
            obj.prepareAutofocusBeamSplitters();
            obj.acquireSampleImageForAutofocus();

            masterRackProxy = obj.getMasterRackProxy();
            if waitForTargets
                masterRackProxy.rackSetWrite([obj.T_channelName; obj.B_channelName], [obj.targetT; obj.targetB]);
            end

            deadline = datetime("now") + waitTimeout;
            noCorrectionStart = NaT;
            sampleCapacity = max(3, ceil(seconds(obj.temperatureStableWindow) / max(seconds(obj.compensationInterval), 1)) + 2);
            temperatureTimes = NaT(sampleCapacity, 1);
            temperatureSamples_K = NaN(sampleCapacity, 1);
            temperatureSampleCount = 0;
            settledCorrectionCount = 0;
            lastDiagnosticTime = datetime("now");

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
                if datetime("now") - lastDiagnosticTime >= obj.diagnosticInterval
                    obj.writeAutofocusDiagnostic(operationName + "_periodic", correction, currentTB);
                    lastDiagnosticTime = datetime("now");
                end
                targetsSettled = (~waitForTargets || obj.targetsReached(currentTB)) ...
                    && obj.temperatureIsStable(temperatureTimes(1:temperatureSampleCount), temperatureSamples_K(1:temperatureSampleCount));

                if targetsSettled && ~correction.didApplyCorrection
                    if isnat(noCorrectionStart)
                        noCorrectionStart = nowTime;
                    elseif nowTime - noCorrectionStart >= obj.noCorrectionQuietDuration
                        obj.writeAutofocusDiagnostic(operationName + "_converged", correction, currentTB);
                        obj.restoreMeasurementOptics();
                        clear cleanup;
                        return;
                    end
                else
                    noCorrectionStart = NaT;
                end

                if targetsSettled && correction.didApplyCorrection
                    settledCorrectionCount = settledCorrectionCount + 1;
                    if settledCorrectionCount >= obj.maxAutofocusIterations
                        error("virtualInstrument_attodryAutofocus:AutofocusConvergenceFailed", ...
                            "Autofocus/autoshift still required correction after %d cycles at settled T/B.", obj.maxAutofocusIterations);
                    end
                elseif ~targetsSettled || ~correction.didApplyCorrection
                    settledCorrectionCount = 0;
                end

                if nowTime >= deadline
                    if waitForTargets
                        error("virtualInstrument_attodryAutofocus:TargetTimeout", ...
                            "Timed out waiting for T/B targets. Target=[%.6g, %.6g], current=[%.6g, %.6g].", ...
                            obj.targetT, obj.targetB, currentTB(1), currentTB(2));
                    else
                        error("virtualInstrument_attodryAutofocus:CooldownTimeout", ...
                            "Timed out waiting for cooldown stabilization. Current T/B=[%.6g, %.6g].", ...
                            currentTB(1), currentTB(2));
                    end
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

            vZ = vz;
            threshold = 1e-4;
            for nTrial = 1:obj.zStepTrialCount
                while true
                    masterRackProxy.rackSetWrite(obj.ANC300_voltage_z_ChannelName, vZ);
                    img0 = obj.acquireSampleImageForAutofocus();
                    s0 = obj.tenengradSharpness(img0);
                    threshold = max(obj.tenengradThreshold * max(abs(s0), eps), 1e-4);
                    anc.stepAxis("z", nTrial);
                    imgPlus = obj.acquireSampleImageForAutofocus();
                    sPlus = obj.tenengradSharpness(imgPlus);
                    anc.stepAxis("z", -2 * nTrial);
                    imgMinus = obj.acquireSampleImageForAutofocus();
                    sMinus = obj.tenengradSharpness(imgMinus);
                    anc.stepAxis("z", nTrial);
                    if max(abs([sPlus - s0, sMinus - s0])) < threshold
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
                obj.zStepTrialCount, threshold, vZ);
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
            correctionSteps = max(min(correctionSteps, obj.maxAutoshiftCorrectionStepsPerAxis), -obj.maxAutoshiftCorrectionStepsPerAxis);
            nStepX = correctionSteps(1);
            nStepY = correctionSteps(2);
            obj.stepXYInSmallChunks(anc, nStepX, nStepY);
        end

        function xyPixelPerStepMatrix = calibrateXYPixelPerStepMatrix(obj)
            obj.xyPixelPerStepMatrix = NaN(2, 2);
            masterRackProxy = obj.getMasterRackProxy();
            anc = obj.getANC300Handle();
            stepTargetPx = obj.targetStepSizePixel;
            calibrationTargetPx = obj.xyCalibrationTargetDisplacement_px;
            oscillationSteps = min(obj.maxAutoshiftCalibrationSteps, max(1, ceil(calibrationTargetPx / stepTargetPx)));
            minAcceptedPxPerStep = stepTargetPx * (1 - obj.xyCalibrationStepSizeToleranceFraction);
            maxAcceptedPxPerStep = stepTargetPx * (1 + obj.xyCalibrationStepSizeToleranceFraction);
            minAcceptedDisplacementPx = calibrationTargetPx * (1 - obj.xyCalibrationStepSizeToleranceFraction);
            [firstTryVoltages, currentTemperature_K] = obj.getInitialPositionerVoltages();
            axes = ["x"; "y"];
            voltageChannels = [obj.ANC300_voltage_x_ChannelName; obj.ANC300_voltage_y_ChannelName];
            xyPixelPerStepMatrix = NaN(2, 2);
            finalVoltages = NaN(2, 1);
            for axisIndex = 1:2
                voltage = max(1, firstTryVoltages(1) * obj.xyCalibrationInitialVoltageScale);
                for voltageAttempt = 1:40
                    masterRackProxy.rackSetWrite(voltageChannels(axisIndex), voltage);
                    [axisVector, maxMeasuredPx, scanRsquare, residualRms_px, returnDrift_px, minFitRsquare] = ...
                        obj.measureAxisOscillationResponse(anc, axes(axisIndex), oscillationSteps);
                    pxPerStep = norm(axisVector);

                    if minFitRsquare < obj.xyCalibrationMinFitRsquare
                        if voltage > 1
                            voltage = max(1, voltage / obj.zVoltageIncrementFactor);
                            continue;
                        end
                        break;
                    end
                    if pxPerStep > maxAcceptedPxPerStep
                        if voltage > 1
                            voltage = obj.adjustXYCalibrationVoltage(voltage, pxPerStep, -1);
                            continue;
                        end
                        break;
                    end
                    if (pxPerStep < minAcceptedPxPerStep || maxMeasuredPx < minAcceptedDisplacementPx) && voltage < 60
                        currentPxPerStep = min(pxPerStep, maxMeasuredPx / oscillationSteps);
                        voltage = obj.adjustXYCalibrationVoltage(voltage, currentPxPerStep, 1);
                        continue;
                    end
                    if scanRsquare < obj.xyCalibrationMinSlopeRsquare ...
                            || residualRms_px > obj.xyCalibrationMaxResidual_px ...
                            || returnDrift_px > obj.xyCalibrationReturnTolerance_px
                        if voltage > 1
                            voltage = max(1, voltage / obj.zVoltageIncrementFactor);
                            continue;
                        end
                        break;
                    end
                    if pxPerStep >= minAcceptedPxPerStep && pxPerStep <= maxAcceptedPxPerStep ...
                            && maxMeasuredPx >= minAcceptedDisplacementPx
                        xyPixelPerStepMatrix(:, axisIndex) = axisVector;
                        finalVoltages(axisIndex) = voltage;
                        break;
                    end
                    break;
                end
            end
            if any(~isfinite(xyPixelPerStepMatrix(:, 1)))
                error("virtualInstrument_attodryAutofocus:XAutoshiftCalibrationFailed", ...
                    "X oscillation calibration could not produce %.6g px displacement with %.6g px/step target within %d steps.", ...
                    obj.xyCalibrationTargetDisplacement_px, obj.targetStepSizePixel, oscillationSteps);
            end
            if any(~isfinite(xyPixelPerStepMatrix(:, 2)))
                error("virtualInstrument_attodryAutofocus:YAutoshiftCalibrationFailed", ...
                    "Y oscillation calibration could not produce %.6g px displacement with %.6g px/step target within %d steps.", ...
                    obj.xyCalibrationTargetDisplacement_px, obj.targetStepSizePixel, oscillationSteps);
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

        function [axisVector, maxMeasuredPx, scanRsquare, residualRms_px, returnDrift_px, minFitRsquare] = measureAxisOscillationResponse(obj, anc, axisName, oscillationSteps)
            signedSteps = NaN(2 * obj.xyCalibrationOscillationCycles, 1);
            offsetDeltas = NaN(2 * obj.xyCalibrationOscillationCycles, 2);
            fitRsquare = NaN(3 * obj.xyCalibrationOscillationCycles, 1);
            currentCommandedStep = 0;
            sampleIndex = 0;
            fitIndex = 0;
            try
                for cycleIndex = 1:obj.xyCalibrationOscillationCycles
                    obj.runZAutofocus();
                    [baselineDx, baselineDy, baselineGof] = obj.estimateSampleOffset(obj.acquireSampleImageForAutoshift());
                    baselineOffset = [baselineDx, baselineDy];
                    fitIndex = fitIndex + 1;
                    fitRsquare(fitIndex) = baselineGof.rsquare;
                    for direction = [1, -1]
                        stepDelta = direction * oscillationSteps;
                        anc.stepAxis(axisName, stepDelta);
                        currentCommandedStep = currentCommandedStep + stepDelta;
                        obj.runZAutofocus();
                        [dx, dy, gof] = obj.estimateSampleOffset(obj.acquireSampleImageForAutoshift());
                        sampleIndex = sampleIndex + 1;
                        signedSteps(sampleIndex) = stepDelta;
                        offsetDeltas(sampleIndex, :) = [dx, dy] - baselineOffset;
                        fitIndex = fitIndex + 1;
                        fitRsquare(fitIndex) = gof.rsquare;
                        anc.stepAxis(axisName, -stepDelta);
                        currentCommandedStep = currentCommandedStep - stepDelta;
                    end
                end
            catch scanError
                obj.returnAxisToScanStart(anc, axisName, currentCommandedStep);
                rethrow(scanError);
            end

            obj.returnAxisToScanStart(anc, axisName, currentCommandedStep);
            obj.runZAutofocus();
            [returnDx, returnDy, returnGof] = obj.estimateSampleOffset(obj.acquireSampleImageForAutoshift());
            [axisVector, scanRsquare, residualRms_px] = obj.fitAxisScanResponse(signedSteps, offsetDeltas);
            maxMeasuredPx = max(sqrt(sum(offsetDeltas.^2, 2)));
            returnDrift_px = norm([returnDx, returnDy] - baselineOffset);
            minFitRsquare = min([fitRsquare; returnGof.rsquare]);
        end

        function [axisVector, scanRsquare, residualRms_px] = fitAxisScanResponse(~, scanPositions, offsets)
            if any(scanPositions(:) == 0)
                error("virtualInstrument_attodryAutofocus:InvalidCalibrationScan", ...
                    "XY calibration scan positions must be nonzero.");
            end
            perStepResponse = offsets ./ scanPositions(:);
            axisVector = median(perStepResponse, 1, "omitnan").';
            residuals = offsets - scanPositions(:) * axisVector.';
            residualRms_px = sqrt(mean(sum(residuals.^2, 2)));
            centered = offsets - median(offsets, 1, "omitnan");
            totalVariance = sum(centered(:).^2);
            if totalVariance > 0
                scanRsquare = 1 - sum(residuals(:).^2) / totalVariance;
            else
                scanRsquare = 0;
            end
        end

        function voltage = adjustXYCalibrationVoltage(obj, voltage, currentPxPerStep, direction)
            if ~(isfinite(currentPxPerStep) && currentPxPerStep >= 0)
                error("virtualInstrument_attodryAutofocus:InvalidCalibrationResponse", ...
                    "XY calibration px/step response must be finite and nonnegative.");
            end
            if direction ~= 1 && direction ~= -1
                error("virtualInstrument_attodryAutofocus:InvalidVoltageDirection", ...
                    "XY calibration voltage direction must be +1 or -1.");
            end
            fractionalError = abs(currentPxPerStep - obj.targetStepSizePixel) / obj.targetStepSizePixel;
            factor = 1 + min(obj.xyCalibrationMaxVoltageFactor - 1, fractionalError);
            if direction > 0
                voltage = min(60, voltage * factor);
            else
                voltage = max(1, voltage / factor);
            end
        end

        function stepAxisInSmallChunks(obj, anc, axisName, nSteps)
            remainingSteps = nSteps;
            while remainingSteps ~= 0
                stepDelta = sign(remainingSteps) * min(abs(remainingSteps), obj.xyCalibrationStepIncrement);
                anc.stepAxis(axisName, stepDelta);
                remainingSteps = remainingSteps - stepDelta;
            end
        end

        function stepXYInSmallChunks(obj, anc, nStepsX, nStepsY)
            remainingSteps = [nStepsX; nStepsY];
            while any(remainingSteps ~= 0)
                stepDelta = sign(remainingSteps) .* min(abs(remainingSteps), obj.xyCalibrationStepIncrement);
                anc.stepXY(stepDelta(1), stepDelta(2));
                remainingSteps = remainingSteps - stepDelta;
            end
        end

        function returnAxisToScanStart(obj, anc, axisName, currentCommandedStep)
            if currentCommandedStep ~= 0
                obj.stepAxisInSmallChunks(anc, axisName, -currentCommandedStep);
            end
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

        function prepareAutofocusBeamSplitters(obj)
            obj.assertOpticsChannelsConfigured();
            if any(~isfinite([obj.BS_camera_likelyOn_PositionDeg, obj.BS_camera_likelyOff_PositionDeg, ...
                    obj.BS_LED_likelyOn_PositionDeg, obj.BS_LED_likelyOff_PositionDeg]))
                obj.characterizeBeamSplitterEndpoints();
            end
            masterRackProxy = obj.getMasterRackProxy();
            currentPositionsDeg = masterRackProxy.rackGet([obj.BS_camera_positionChannelName; obj.BS_LED_positionChannelName]);
            currentPositionsDeg = currentPositionsDeg(:);
            if numel(currentPositionsDeg) ~= 2 || any(~isfinite(currentPositionsDeg))
                error("virtualInstrument_attodryAutofocus:InvalidBeamSplitterPositionRead", ...
                    "Expected finite camera and LED beam splitter position reads.");
            end
            if abs(currentPositionsDeg(1) - obj.BS_camera_likelyOn_PositionDeg) > obj.bsPositionToleranceDeg
                obj.setBeamSplitterState("camera", true);
            end
            if abs(currentPositionsDeg(2) - obj.BS_LED_likelyOn_PositionDeg) > obj.bsPositionToleranceDeg
                obj.setBeamSplitterState("LED", true);
            end
        end

        function restoreMeasurementOptics(obj)
            obj.setLEDState(false);
            obj.setLaserPathState(blocked = true, ndOn = false);
            if obj.turnBeamSplittersOffAfterAutofocus
                obj.setBeamSplitterState("LED", false);
                obj.setBeamSplitterState("camera", false);
            end
        end

        function blockLaserOnly(obj)
            obj.setLaserPathState(blocked = true, ndOn = false);
        end

        function image2D = acquireSampleImageForAutofocus(obj)
            obj.setLaserPathState(blocked = true, ndOn = false);
            obj.setLEDState(true);
            image2D = obj.acquireCameraImage();
        end

        function image2D = acquireSampleImageForAutoshift(obj)
            image2D = obj.acquireSampleImageForAutofocus();
        end

        function image2D = acquireLaserSpotImage(obj)
            obj.setLEDState(false);
            obj.setLaserPathState(blocked = false, ndOn = true);
            image2D = obj.acquireCameraImage();
        end

        function [image2D, center_px, stats] = acquireLaserSpotImageAndCenter(obj)
            image2D = obj.acquireLaserSpotImage();
            [center_px, stats] = obj.estimateBeamspotCenterInternal(image2D, obj.referenceBeamspot_px);
        end

        function image2D = acquireDiagnosticSampleBeamspotImage(obj)
            obj.prepareAutofocusBeamSplitters();
            obj.setLEDState(true);
            obj.setLaserPathState(blocked = false, ndOn = true);
            image2D = obj.acquireCameraImage();
        end

        function writeAutofocusDiagnostic(obj, reason, correction, currentTB)
            outputFolder = obj.diagnosticOutputFolder;
            if ~isfolder(outputFolder)
                [status, message] = mkdir(outputFolder);
                if ~status
                    error("virtualInstrument_attodryAutofocus:DiagnosticFolderCreateFailed", ...
                        "Failed to create diagnostic output folder %s: %s", outputFolder, message);
                end
            end

            cleanup = onCleanup(@() obj.blockLaserOnly());
            diagnosticZSteps = 0;
            if obj.anc300Configured() && isfield(correction, "xySteps") && any(correction.xySteps(:) ~= 0)
                diagnosticZSteps = obj.runZAutofocus();
            end
            diagnosticImage = obj.acquireDiagnosticSampleBeamspotImage();
            obj.blockLaserOnly();
            clear cleanup;

            beamspot_px = obj.lastBeamspot_px;
            beamspotStats = struct("source", "lastBeamspot_px");
            if any(~isfinite(beamspot_px))
                error("virtualInstrument_attodryAutofocus:MissingDiagnosticBeamspot", ...
                    "Diagnostic beamspot marker requires a finite laser-only beamspot from the latest correction cycle.");
            end
            markedImage = obj.renderBeamspotDiagnosticImage(diagnosticImage, beamspot_px);

            timestamp = datetime("now");
            timestampForName = timestamp;
            timestampForName.Format = "yyyyMMdd_HHmmss_SSS";
            reasonTag = string(regexprep(char(reason), "[^A-Za-z0-9_]+", "_"));
            fileBase = "attodry_af_" + string(timestampForName) + "_" + reasonTag;
            pngPath = fullfile(outputFolder, fileBase + ".png");
            matPath = fullfile(outputFolder, fileBase + ".mat");

            imwrite(markedImage, pngPath);
            diagnostic = struct( ...
                "timestamp", timestamp, ...
                "reason", string(reason), ...
                "rawImage", diagnosticImage, ...
                "markedImage", markedImage, ...
                "beamspot_px", beamspot_px, ...
                "beamspotStats", beamspotStats, ...
                "referenceBeamspot_px", obj.referenceBeamspot_px, ...
                "lastBeamspotDelta_px", obj.lastBeamspotDelta_px, ...
                "currentTB", currentTB(:), ...
                "targetTB", [obj.targetT; obj.targetB], ...
                "correction", correction, ...
                "diagnosticZSteps", diagnosticZSteps, ...
                "imageMode", "LED on, ND-protected laser path unblocked", ...
                "offsetFitRoi_px", obj.offsetFitRoi_px, ...
                "pngPath", pngPath, ...
                "matPath", matPath);
            save(matPath, "diagnostic", "-v7.3");
        end

        function markedImage = renderBeamspotDiagnosticImage(obj, image2D, center_px)
            img = double(image2D);
            if any(~isfinite(img(:)))
                error("virtualInstrument_attodryAutofocus:InvalidDiagnosticImage", ...
                    "Diagnostic image must contain only finite values.");
            end
            [rows, cols] = size(img);
            if numel(center_px) ~= 2 || any(~isfinite(center_px))
                error("virtualInstrument_attodryAutofocus:InvalidDiagnosticBeamspot", ...
                    "Diagnostic beamspot coordinates must be finite [x; y].");
            end
            xCenter = round(center_px(1));
            yCenter = round(center_px(2));
            if xCenter < 1 || xCenter > cols || yCenter < 1 || yCenter > rows
                error("virtualInstrument_attodryAutofocus:DiagnosticBeamspotOutOfBounds", ...
                    "Diagnostic beamspot [%.3f, %.3f] is outside image size [%d, %d].", ...
                    center_px(1), center_px(2), cols, rows);
            end

            low = obj.percentileValue(img(:), 1);
            high = obj.percentileValue(img(:), 99.7);
            if high <= low
                low = min(img(:));
                high = max(img(:));
            end
            if high <= low
                grayImage = zeros(rows, cols, "uint8");
            else
                grayImage = uint8(round(255 * max(0, min(1, (img - low) ./ (high - low)))));
            end
            markedImage = repmat(grayImage, 1, 1, 3);

            lineLower = floor((obj.diagnosticCrosshairLineWidth_px - 1) / 2);
            lineUpper = ceil((obj.diagnosticCrosshairLineWidth_px - 1) / 2);
            xLine = max(1, xCenter - lineLower):min(cols, xCenter + lineUpper);
            yLine = max(1, yCenter - lineLower):min(rows, yCenter + lineUpper);
            leftArm = max(1, xCenter - obj.diagnosticCrosshairArm_px):min(cols, xCenter - obj.diagnosticCrosshairGap_px);
            rightArm = max(1, xCenter + obj.diagnosticCrosshairGap_px):min(cols, xCenter + obj.diagnosticCrosshairArm_px);
            topArm = max(1, yCenter - obj.diagnosticCrosshairArm_px):min(rows, yCenter - obj.diagnosticCrosshairGap_px);
            bottomArm = max(1, yCenter + obj.diagnosticCrosshairGap_px):min(rows, yCenter + obj.diagnosticCrosshairArm_px);

            mask = false(rows, cols);
            mask(yLine, leftArm) = true;
            mask(yLine, rightArm) = true;
            mask(topArm, xLine) = true;
            mask(bottomArm, xLine) = true;

            markerColor = uint8([255, 64, 0]);
            for colorIndex = 1:3
                colorPlane = markedImage(:, :, colorIndex);
                colorPlane(mask) = markerColor(colorIndex);
                markedImage(:, :, colorIndex) = colorPlane;
            end
        end

        function correctedOffset_px = computeBeamReferencedSampleOffset(obj, rawOffset_px, liveBeamspot_px)
            if any(~isfinite(obj.referenceBeamspot_px)) || any(~isfinite(liveBeamspot_px))
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotReference", ...
                    "Reference and live beamspot coordinates must be finite.");
            end
            beamDelta_xy = liveBeamspot_px(:) - obj.referenceBeamspot_px(:); % [x; y] = [column; row]
            commonImageOffset_px = [beamDelta_xy(2); beamDelta_xy(1)];
            correctedOffset_px = rawOffset_px(:) - commonImageOffset_px;
        end

        function [center_px, stats] = estimateBeamspotCenterInternal(obj, image2D, startCenter_px)
            if isempty(image2D)
                error("virtualInstrument_attodryAutofocus:EmptyBeamspotImage", ...
                    "Beamspot image is empty.");
            end
            img = double(image2D);
            if any(~isfinite(img(:)))
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotImage", ...
                    "Beamspot image must contain only finite values.");
            end

            [rows, cols] = size(img);
            fitRows = 1:rows;
            fitCols = 1:cols;
            roi_px = [1, 1, cols, rows];
            roiImg = img;
            [xGrid, yGrid] = meshgrid(fitCols, fitRows);

            background = obj.percentileValue(roiImg(:), obj.beamspotBackgroundPercentile);
            signal = roiImg - background;
            signal(signal < 0) = 0;
            if obj.beamspotWeightPower ~= 1
                signal = signal .^ obj.beamspotWeightPower;
            end
            totalSignal = sum(signal(:));
            if totalSignal <= 0
                error("virtualInstrument_attodryAutofocus:BeamspotSignalMissing", ...
                    "Beamspot signal is zero after background subtraction.");
            end

            if numel(startCenter_px) == 2 && all(isfinite(startCenter_px)) ...
                    && startCenter_px(1) >= min(fitCols) && startCenter_px(1) <= max(fitCols) ...
                    && startCenter_px(2) >= min(fitRows) && startCenter_px(2) <= max(fitRows)
                centerX = startCenter_px(1);
                centerY = startCenter_px(2);
            else
                centerX = sum(xGrid(:) .* signal(:)) / totalSignal;
                centerY = sum(yGrid(:) .* signal(:)) / totalSignal;
            end

            radius_px = obj.beamspotCircleRadius_px;
            if ~isfinite(radius_px)
                radius_px = 0.45 * min(numel(fitRows), numel(fitCols));
            end
            if radius_px <= 0
                error("virtualInstrument_attodryAutofocus:InvalidBeamspotCircleRadius", ...
                    "Computed beamspot circular ROI radius must be positive.");
            end

            for iterationIndex = 1:obj.beamspotCenterIterations
                circularMask = (xGrid - centerX).^2 + (yGrid - centerY).^2 <= radius_px.^2;
                weights = signal;
                weights(~circularMask) = 0;
                weightSum = sum(weights(:));
                if weightSum <= 0
                    error("virtualInstrument_attodryAutofocus:BeamspotSignalMissingInCircle", ...
                        "Beamspot circular ROI contains no positive signal.");
                end
                nextCenterX = sum(xGrid(:) .* weights(:)) / weightSum;
                nextCenterY = sum(yGrid(:) .* weights(:)) / weightSum;
                if hypot(nextCenterX - centerX, nextCenterY - centerY) <= obj.beamspotCenterTolerance_px
                    centerX = nextCenterX;
                    centerY = nextCenterY;
                    break;
                end
                centerX = nextCenterX;
                centerY = nextCenterY;
            end

            center_px = [centerX; centerY];
            beamDeltaFromStart_px = [NaN; NaN];
            if numel(startCenter_px) == 2 && all(isfinite(startCenter_px))
                beamDeltaFromStart_px = center_px - startCenter_px(:);
            end
            stats = struct( ...
                "background", background, ...
                "totalSignal", totalSignal, ...
                "radius_px", radius_px, ...
                "roi_px", roi_px, ...
                "deltaFromStart_px", beamDeltaFromStart_px);
        end

        function p = percentileValue(~, values, percentile)
            values = sort(values(:));
            n = numel(values);
            if n == 0
                p = NaN;
                return;
            end
            if percentile <= 0
                p = values(1);
                return;
            elseif percentile >= 100
                p = values(end);
                return;
            end
            idx = 1 + (n - 1) * percentile / 100;
            lo = floor(idx);
            hi = ceil(idx);
            if lo == hi
                p = values(lo);
            else
                alpha = idx - lo;
                p = (1 - alpha) * values(lo) + alpha * values(hi);
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

        function setLEDState(obj, LEDOn)
            if LEDOn
                if obj.colorStored == 0
                    RGB = [1; 0; 0];  % red
                else
                    RGB = [0; 1; 0];  % green
                end
            else
                RGB = [0; 0; 0];
            end

            masterRackProxy = obj.getMasterRackProxy();
            masterRackProxy.rackSet(obj.LEDRGBChannelName, RGB);
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
            isColorCamera = isprop(cameraHandle, "isColorCamera") && cameraHandle.isColorCamera;
            cameraClass = string(class(cameraHandle));
            isCS165Camera = ismember(obj.cameraInstrumentFriendlyName, ["CS165MU", "CS165CU"]) ...
                || ismember(cameraClass, ["instrument_CS165MU", "instrument_CS165CU"]);
            if isColorCamera
                if strlength(obj.cameraColorChannelName) == 0
                    error("virtualInstrument_attodryAutofocus:CameraColorChannelMissing", ...
                        "Color camera autofocus requires cameraColorChannelName, e.g. cam_c.");
                end
                masterRackProxy.rackSet(obj.cameraColorChannelName, obj.colorStored);
            end
            if ismethod(cameraHandle, "stopContinuousAcquisitionForAutofocus")
                cameraHandle.stopContinuousAcquisitionForAutofocus();
            elseif isCS165Camera
                error("virtualInstrument_attodryAutofocus:CameraStopContinuousMethodMissing", ...
                    "CS165 autofocus acquisition requires camera method stopContinuousAcquisitionForAutofocus().");
            end
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

            obj.referenceFilteredImage = referenceFiltered;
            obj.referenceFitSize_px = [rows, cols];
            obj.referenceFitTrim_px = [xTrim, yTrim];
        end

        function [fitRows, fitCols] = getOffsetFitRoiIndices(obj, imageSize, roiShift_xy)
            if nargin < 3
                roiShift_xy = [0; 0];
            end
            if ~(isnumeric(roiShift_xy) && numel(roiShift_xy) == 2 && all(isfinite(roiShift_xy(:))))
                error("virtualInstrument_attodryAutofocus:InvalidOffsetFitRoiShift", ...
                    "offsetFitRoi shift must be finite [x; y] pixels.");
            end
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
            roi(1:2) = roi(1:2) + reshape(roiShift_xy, 1, 2);

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

        function updateCameraOffsetFitOverlay(obj, roiShift_xy)
            masterRackProxy = obj.getMasterRackProxy();
            cameraHandle = masterRackProxy.getReviewedInstrumentHandleForNonChannelMethod( ...
                obj.cameraInstrumentFriendlyName, "", "autofocus camera live ROI overlay");
            cameraClass = string(class(cameraHandle));
            isCS165Camera = ismember(obj.cameraInstrumentFriendlyName, ["CS165MU", "CS165CU"]) ...
                || ismember(cameraClass, ["instrument_CS165MU", "instrument_CS165CU"]);
            if all(isnan(obj.offsetFitRoi_px))
                if ismethod(cameraHandle, "clearLiveOverlayRoi")
                    cameraHandle.clearLiveOverlayRoi();
                elseif isCS165Camera
                    error("virtualInstrument_attodryAutofocus:CameraOverlayMethodMissing", ...
                        "CS165 live ROI overlay requires clearLiveOverlayRoi().");
                end
                return;
            end
            if ~ismethod(cameraHandle, "setLiveOverlayRoi")
                if isCS165Camera
                    error("virtualInstrument_attodryAutofocus:CameraOverlayMethodMissing", ...
                        "CS165 live ROI overlay requires setLiveOverlayRoi().");
                end
                return;
            end
            roi_px = obj.offsetFitRoi_px;
            roi_px(1:2) = roi_px(1:2) + reshape(roiShift_xy, 1, 2);
            cameraHandle.setLiveOverlayRoi(roi_px);
            cameraHandle.setLiveOverlayEnabled(true);
        end

        function assertReferenceFitReady(obj)
            if isempty(obj.referenceSampleImage) || isempty(obj.referenceFilteredImage)
                error("virtualInstrument_attodryAutofocus:MissingReferenceData", ...
                    "Call takeReferenceData() before estimating sample offsets.");
            end
        end

        function assertChannelsExist(obj, channelNames)
            channelNames = unique(channelNames(:));
            obj.getMasterRackProxy().assertChannelsExist(channelNames);
        end

        function assertOpticsChannelsConfigured(obj)
            if obj.colorStored == 0
                laserLabels = ["block_red_positionChannelName"; "ND_red_positionChannelName"];
                laserValues = [obj.block_red_positionChannelName; obj.ND_red_positionChannelName];
            elseif obj.colorStored == 1
                laserLabels = ["block_green_positionChannelName"; "ND_green_positionChannelName"];
                laserValues = [obj.block_green_positionChannelName; obj.ND_green_positionChannelName];
            else
                error("virtualInstrument_attodryAutofocus:InvalidColor", ...
                    "color must be 0 (red) or 1 (green).");
            end

            commonLabels = [ ...
                "BS_camera_positionChannelName"; ...
                "BS_LED_positionChannelName"; ...
                "BS_camera_setConsistentlyChannelName"; ...
                "BS_LED_setConsistentlyChannelName"; ...
                "LEDRGBChannelName"];

            commonValues = [ ...
                obj.BS_camera_positionChannelName; ...
                obj.BS_LED_positionChannelName; ...
                obj.BS_camera_setConsistentlyChannelName; ...
                obj.BS_LED_setConsistentlyChannelName; ...
                obj.LEDRGBChannelName];

            labels = [laserLabels; commonLabels];
            values = [laserValues; commonValues];

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
