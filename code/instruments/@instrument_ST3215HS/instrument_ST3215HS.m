classdef instrument_ST3215HS < instrumentInterface
    % Control ST3215-HS bus servos via Waveshare Bus Servo Adapter (A)
    %
    % Protocol is adapted directly from Waveshare SCServo Arduino library:
    % temp/waveshare servo/ST Servo/SCServo/{SCS.cpp, SMS_STS.cpp}
    %
    % IMPORTANT: Power the servo(s) from 12V. The reported load_*_percent depends
    % on supply voltage; if you use a different voltage, the stall/stop threshold
    % used by calibrateSoftLimits() may need to be changed.
    %
    % Channels:
    %   - "position_1_deg" : servo 1 position in degrees
    %   - "load_1_percent" : servo 1 load (signed percent, -100..+100)
    %   - "setConsistently_1" : servo 1 position mode (0 = direct set, 1 = setPositionConsistent)
    %   - "position_2_deg" : servo 2 position in degrees
    %   - "load_2_percent" : servo 2 load (signed percent, -100..+100)
    %   - "setConsistently_2" : servo 2 position mode (0 = direct set, 1 = setPositionConsistent)
    %
    % Example:
    %   s = instrument_ST3215HS("COM6", servoId_1=1);          % one servo
    %   s = instrument_ST3215HS("COM6", servoId_1=1, servoId_2=2); % two servos
    %   rack.addInstrument(s, "servo");
    %   rack.addChannel("servo", "position_1_deg", "servo1Pos_deg");
    %   rack.addChannel("servo", "load_1_percent", "servo1Load_percent");
    %
    %   % Note: speed/acceleration are intentionally fixed inside the instrument
    %   % to keep settling behavior consistent.
    %   rack.rackSet("servo1Pos_deg", 180);
    %   p = rack.rackGet("servo1Pos_deg");

    properties
        % IDs on the servo bus (0..253). 254 (0xFE) is broadcast (no response).
        servoId_1 (1, 1) uint8 = uint8(1);
        % ID for optional second servo (meaningful only when hasServo2 is true).
        servoId_2 (1, 1) uint8 = uint8(0);

        % Conversion factor between servo raw position ticks and degrees.
        % Waveshare examples commonly use 0..4095 ticks over ~360 degrees.
        % angle_deg = raw_ticks / ticksPerDegree
        ticksPerDegree (1, 1) double {mustBePositive} = 4096 / 360;

        % Default threshold used by calibrateSoftLimits().
        % IMPORTANT: This threshold is only meaningful if the servo is powered from 12V.
        defaultLoadThreshold_percent (1, 1) double {mustBePositive} = 6;

        % Delay between the two reads used by setCheckChannelHelper() for
        % "settled-ness" detection. A small nonzero delay helps avoid false
        % positives when the servo is still moving but consecutive reads happen
        % to quantize to the same tick.
        setCheckInterReadDelay_s (1, 1) double {mustBeNonnegative} = 0.1;
    end

    properties (SetAccess = private)
        % Speed in degrees (deg-equivalent; converted to servo raw units when sending WritePosEx).
        % Fixed to keep settling behavior consistent and comparable across runs.
        speed (1, 1) double = 300;

        % Acceleration in degrees (deg-equivalent; converted to servo raw units when sending WritePosEx).
        % Fixed to keep settling behavior consistent and comparable across runs.
        acceleration (1, 1) double = 10;
    end

    properties (SetAccess = private)
        hasServo2 (1, 1) logical = false;
        useSetPositionConsistent_1 (1, 1) logical = false;
        useSetPositionConsistent_2 (1, 1) logical = false;

        % Soft limits (degrees) found by calibrateSoftLimits().
        % Defaults are unbounded to simplify bring-up/testing.
        softMin_1_deg (1, 1) double = -Inf;
        softMax_1_deg (1, 1) double = Inf;
        softMin_2_deg (1, 1) double = -Inf;
        softMax_2_deg (1, 1) double = Inf;
    end

    properties (Access = private)
        ioTimeoutSeconds (1, 1) double = 0.2;
        bypassConsistentPositionSet_ (1, 1) logical = false;
    end

    properties (Constant, Access = private)
        % INST.h
        INST_PING = uint8(hex2dec("01"));
        INST_READ = uint8(hex2dec("02"));
        INST_WRITE = uint8(hex2dec("03"));

        % SMS_STS.h memory table addresses
        SMS_STS_ACC = uint8(41);
        SMS_STS_PRESENT_POSITION_L = uint8(56);
        SMS_STS_PRESENT_LOAD_L = uint8(60);

        % Waveshare reference code uses 4000 as the max ST-series speed value.
        % (e.g. temp/waveshare servo/ST Servo/ServoDriverST/STSCTRL.h)
        STS_MAX_SPEED_RAW = uint16(4000);
        STS_MAX_ACC_RAW = uint8(255);
    end

    methods (Static)
        reprogramSTServoId(comPort, idFrom, idTo, NameValueArgs);
    end

    methods
        function obj = instrument_ST3215HS(address, varargin)
            % Constructor
            %
            % Usage:
            %   s = instrument_ST3215HS("COM6");
            %   s = instrument_ST3215HS("COM6", servoId_1=1, baudRate=1000000);
            %   s = instrument_ST3215HS("COM6", servoId_1=1, servoId_2=2, baudRate=1000000);
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
            end
            arguments (Repeating)
                varargin
            end

            obj@instrumentInterface();

            opts = instrument_ST3215HS.parseConstructorArgs_(varargin{:});

            % Validate IDs before touching hardware (serialport) so user errors are fast/clear.
            if isfield(opts, "servoId_1")
                servoId_1 = opts.servoId_1;
            else
                servoId_1 = 1;
            end
            obj.servoId_1 = uint8(instrument_ST3215HS.validateServoIdOrError_(servoId_1, "servoId_1"));
            if isfield(opts, "servoId_2")
                obj.hasServo2 = true;
                obj.servoId_2 = uint8(instrument_ST3215HS.validateServoIdOrError_(opts.servoId_2, "servoId_2"));
            else
                obj.hasServo2 = false;
                obj.servoId_2 = uint8(0); % placeholder; ignored unless hasServo2 is true
            end

            obj.ioTimeoutSeconds = opts.timeoutSeconds;

            obj.address = address;

            sp = serialport(address, opts.baudRate, Timeout = obj.ioTimeoutSeconds);
            sp.FlowControl = "none";
            obj.communicationHandle = sp;

            if ~obj.pingServoId(double(obj.servoId_1), nAttempts = 3)
                error("ST3215HS:PingFailed", ...
                    "No response to PING from servoId_1=%d. Check COM port, baud rate, wiring, and power.", ...
                    double(obj.servoId_1));
            end

            % Channels
            obj.addChannel("position_1_deg");
            % load_* channels are read-only, so setTolerances would be unused/misleading.
            obj.addChannel("load_1_percent");
            obj.addChannel("setConsistently_1");

            % Optional servo 2: only add channels if explicitly enabled
            if obj.hasServo2
                if ~obj.pingServoId(double(obj.servoId_2), nAttempts = 3)
                    error("ST3215HS:PingFailed", ...
                        "servoId_2=%d was provided but did not respond to PING.", double(obj.servoId_2));
                end
                obj.addChannel("position_2_deg");
                % load_* channels are read-only, so setTolerances would be unused/misleading.
                obj.addChannel("load_2_percent");
                obj.addChannel("setConsistently_2");
            end
        end

        function TF = pingServoId(obj, servoId, NameValueArgs)
            % pingServoId Return true if the given servo ID responds to PING.
            arguments
                obj
                servoId (1, 1) double {mustBeInteger}
                NameValueArgs.nAttempts (1, 1) double {mustBeInteger, mustBePositive} = 1
                NameValueArgs.postWritePauseSeconds (1, 1) double {mustBeNonnegative} = 0.003
            end

            servoId = instrument_ST3215HS.validateServoIdOrError_(servoId, "servoId");

            TF = false;
            for k = 1:NameValueArgs.nAttempts
                try
                    obj.flush();
                    obj.sendPing_(uint8(servoId));
                    if NameValueArgs.postWritePauseSeconds > 0
                        pause(NameValueArgs.postWritePauseSeconds);
                    end
                    obj.readAckAllowErr_(uint8(servoId));
                    TF = true;
                    return;
                catch
                end
            end
        end

        function delete(obj)
            try
                if ~isempty(obj.communicationHandle)
                    flush(obj.communicationHandle);
                end
            catch
            end
            try
                if ~isempty(obj.communicationHandle)
                    delete(obj.communicationHandle);
                end
            catch
            end
        end

        function flush(obj)
            if ~isempty(obj.communicationHandle)
                flush(obj.communicationHandle);
            end
        end
    end

    methods
        function result = setPositionConsistent(obj, targetDeg, servoNumber, NameValueArgs)
            % setPositionConsistent
            %
            % Actively "dither" the commanded position to get a more reproducible
            % final equilibrium tick near the target.
            %
            % This is designed for non-continuous rotation servos where wrapping
            % around 0/360 is NOT desired. Excursions are clamped (not mod-wrapped)
            % and the target is validated against soft limits narrowed by a small
            % tick-based buffer.
            %
            % Outcomes:
            % - success by reaching exact tick match (dTick == 0)
            % - success by stalling: dTick unchanged for maxStallCount excursions
            % - error if neither happens within maxExcursions
            %
            % The instrument's normal setChannel settling check is still used to
            % ensure each commanded move has stopped changing before measuring ticks.
            arguments
                obj
                targetDeg (1, 1) double {mustBeFinite}
                servoNumber (1, 1) double {mustBeInteger, mustBeMember(servoNumber, [1, 2])} = 1
                NameValueArgs.verbose (1, 1) logical = false
            end

            % These parameters are intentionally fixed inside the instrument to keep
            % behavior consistent/reproducible across runs. Change them here if needed.
            excursionFactor = 1.5;
            excursionClampTick = 200;
            maxExcursions = 30;
            maxStallCount = 5;
            softLimitBuffer_tick = 5;

            if servoNumber == 1
                positionChannel = "position_1_deg";
                softMin = obj.softMin_1_deg;
                softMax = obj.softMax_1_deg;
            else
                if ~obj.hasServo2
                    error("ST3215HS:Servo2NotEnabled", ...
                        "servoNumber=2 was requested but this instrument was constructed without servoId_2.");
                end
                positionChannel = "position_2_deg";
                softMin = obj.softMin_2_deg;
                softMax = obj.softMax_2_deg;
            end

            % Normalize to [0, 360], preserving 360 as 0 for convenience.
            if targetDeg == 360
                targetDeg = 0;
            end
            if targetDeg < 0 || targetDeg > 360
                error("ST3215HS:InvalidTarget", ...
                    "targetDeg must be within [0, 360]. Received %s.", formattedDisplayText(targetDeg));
            end

            ticksPerRev = round(360 * obj.ticksPerDegree); % should be 4096
            targetTick = round(targetDeg * obj.ticksPerDegree);
            targetTick = max(0, min(ticksPerRev - 1, targetTick));

            % Clamp excursion ticks within buffered soft limits (if finite), else [0..4095].
            minTickAllowed = 0;
            maxTickAllowed = ticksPerRev - 1;
            if isfinite(softMin)
                minTickAllowed = ceil(softMin * obj.ticksPerDegree) + softLimitBuffer_tick;
            end
            if isfinite(softMax)
                maxTickAllowed = floor(softMax * obj.ticksPerDegree) - softLimitBuffer_tick;
            end
            minTickAllowed = max(0, min(ticksPerRev - 1, minTickAllowed));
            maxTickAllowed = max(0, min(ticksPerRev - 1, maxTickAllowed));
            if minTickAllowed > maxTickAllowed
                error("ST3215HS:InvalidSoftLimits", ...
                    "Buffered soft limit ticks are invalid: [%d, %d].", minTickAllowed, maxTickAllowed);
            end
            softMinN = minTickAllowed / obj.ticksPerDegree;
            softMaxN = maxTickAllowed / obj.ticksPerDegree;
            if targetTick < minTickAllowed || targetTick > maxTickAllowed
                error("ST3215HS:TargetOutsideSoftLimits", ...
                    "Requested %.3f deg (tick %d) is outside buffered soft limits [%.3f, %.3f] deg (ticks [%d, %d]).", ...
                    targetDeg, targetTick, softMinN, softMaxN, minTickAllowed, maxTickAllowed);
            end

            % Ensure setChannel uses settle checks.
            prevRequireSetCheck = obj.requireSetCheck;
            obj.requireSetCheck = true;
            cleanupSetCheck = onCleanup(@() obj.restoreRequireSetCheck_(prevRequireSetCheck)); %#ok<NASGU>

            % Prevent recursive re-entry when setPositionConsistent() drives setChannel().
            prevBypassConsistentSet = obj.bypassConsistentPositionSet_;
            obj.bypassConsistentPositionSet_ = true;
            cleanupBypassConsistentSet = onCleanup(@() obj.restoreBypassConsistentPositionSet_(prevBypassConsistentSet)); %#ok<NASGU>

            % Helper: measure tick after a settled setChannel.
            function [dTick, actualTick] = setTargetAndMeasure_()
                obj.setChannel(positionChannel, targetDeg);
                posDeg = obj.getChannel(positionChannel);
                actualTick = round(posDeg * obj.ticksPerDegree);
                actualTick = max(0, min(ticksPerRev - 1, actualTick));
                dTick = actualTick - targetTick;
            end

            if NameValueArgs.verbose
                experimentContext.print("setPositionConsistent: servoNumber=%d targetDeg=%.3f targetTick=%d", servoNumber, targetDeg, targetTick);
            end

            [d0, a0] = setTargetAndMeasure_();
            if NameValueArgs.verbose
                experimentContext.print("  init: actualTick=%d dTick=%+d", a0, d0);
            end

            actualTick = a0;
            dTick = d0;
            nExcursions = 0;

            if dTick == 0
                result = struct( ...
                    "servoNumber", servoNumber, ...
                    "positionChannel", positionChannel, ...
                    "targetDeg", targetDeg, ...
                    "targetTick", targetTick, ...
                    "actualTick", actualTick, ...
                    "dTick", dTick, ...
                    "stopReason", "already_zero", ...
                    "nExcursions", nExcursions);
                return;
            end

            stallCount = 0;
            dPrev = dTick;

            for k = 1:maxExcursions
                excRel = round(-dPrev * excursionFactor);
                excRel = max(-excursionClampTick, min(excursionClampTick, excRel));
                if excRel == 0
                    excRel = -sign(dPrev); % minimum nudge
                end

                excTick = max(minTickAllowed, min(maxTickAllowed, targetTick + excRel));
                excDeg = excTick / obj.ticksPerDegree;

                % Excursion, then explicit return to target.
                obj.setChannel(positionChannel, excDeg);
                [dNew, aNew] = setTargetAndMeasure_();

                if NameValueArgs.verbose
                    experimentContext.print("  iter=%2d dPrev=%+4d excRel=%+4d excTick=%4d -> actualTick=%4d dNew=%+4d", ...
                        k, dPrev, excRel, excTick, aNew, dNew);
                end

                actualTick = aNew;
                dTick = dNew;
                nExcursions = k;

                if dNew == 0
                    result = struct( ...
                        "servoNumber", servoNumber, ...
                        "positionChannel", positionChannel, ...
                        "targetDeg", targetDeg, ...
                        "targetTick", targetTick, ...
                        "actualTick", actualTick, ...
                        "dTick", dTick, ...
                        "stopReason", "reached_zero", ...
                        "nExcursions", nExcursions);
                    return;
                end

                if dNew == dPrev
                    stallCount = stallCount + 1;
                else
                    stallCount = 0;
                end

                if stallCount >= maxStallCount
                    result = struct( ...
                        "servoNumber", servoNumber, ...
                        "positionChannel", positionChannel, ...
                        "targetDeg", targetDeg, ...
                        "targetTick", targetTick, ...
                        "actualTick", actualTick, ...
                        "dTick", dTick, ...
                        "stopReason", "stall", ...
                        "nExcursions", nExcursions);
                    return;
                end

                dPrev = dNew;
            end

            % If we get here: neither reached zero nor stalled in time -> error.
            error("ST3215HS:ActiveSetFailed", ...
                "setPositionConsistent did not reach dTick==0 or stall within maxExcursions=%d (final dTick=%+d).", ...
                maxExcursions, dTick);
        end

        function calibrateSoftLimits(obj, servoNumber, NameValueArgs)
            % calibrateSoftLimits
            %
            % Scans the full servo range in 1-tick increments using setChannel()
            % (and therefore the instrument's settling checks), reading servo load
            % at each step. When |load| exceeds loadThreshold_percent, the
            % last safe position is stored as a soft limit.
            %
            % IMPORTANT: This relies on load_*_percent behavior which depends on
            % supply voltage. Power the servo(s) from 12V, otherwise pass a
            % different loadThreshold_percent when running this.
            %
            % Note: this method temporarily forces requireSetCheck=true to ensure
            % each 1-tick move has actually settled before the load is sampled.
            %
            % Results (read-only):
            %   obj.softMin_1_deg, obj.softMax_1_deg, obj.softMin_2_deg, obj.softMax_2_deg
            arguments
                obj
                servoNumber (1, 1) double {mustBeInteger, mustBeMember(servoNumber, [1, 2])} = 1
                NameValueArgs.verbose (1, 1) logical = false;
                NameValueArgs.loadThreshold_percent (1, 1) double {mustBePositive} = obj.defaultLoadThreshold_percent;
            end

            prevRequireSetCheck = obj.requireSetCheck;
            obj.requireSetCheck = true;
            c = onCleanup(@() obj.restoreRequireSetCheck_(prevRequireSetCheck)); %#ok<NASGU>
            prevBypassConsistentSet = obj.bypassConsistentPositionSet_;
            obj.bypassConsistentPositionSet_ = true;
            cleanupBypassConsistentSet = onCleanup(@() obj.restoreBypassConsistentPositionSet_(prevBypassConsistentSet)); %#ok<NASGU>

            loadThreshold_percent = NameValueArgs.loadThreshold_percent;

            if servoNumber == 1
                positionChannel = "position_1_deg";
                loadChannel = "load_1_percent";

                % Reset to unbounded so setChannel during calibration never fails.
                obj.softMin_1_deg = -Inf;
                obj.softMax_1_deg = Inf;

                [obj.softMin_1_deg, obj.softMax_1_deg] = obj.calibrateSoftLimitsForServo_( ...
                    positionChannel, loadChannel, loadThreshold_percent, NameValueArgs.verbose);
            else
                if ~obj.hasServo2
                    error("ST3215HS:Servo2NotEnabled", ...
                        "servoNumber=2 was requested but this instrument was constructed without servoId_2.");
                end
                positionChannel = "position_2_deg";
                loadChannel = "load_2_percent";

                % Reset to unbounded so setChannel during calibration never fails.
                obj.softMin_2_deg = -Inf;
                obj.softMax_2_deg = Inf;

                [obj.softMin_2_deg, obj.softMax_2_deg] = obj.calibrateSoftLimitsForServo_( ...
                    positionChannel, loadChannel, loadThreshold_percent, NameValueArgs.verbose);
            end
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            % Flush before issuing any read to avoid stale/leftover bytes
            obj.flush();
            switch channelIndex
                case 1 % "position_1_deg"
                    obj.sendRead_(obj.servoId_1, obj.SMS_STS_PRESENT_POSITION_L, uint8(2));
                case 2 % "load_1_percent"
                    obj.sendRead_(obj.servoId_1, obj.SMS_STS_PRESENT_LOAD_L, uint8(2));
                case 3 % "setConsistently_1"
                    % software-only channel; no bus read needed
                case 4 % "position_2_deg"
                    obj.sendRead_(obj.servoId_2, obj.SMS_STS_PRESENT_POSITION_L, uint8(2));
                case 5 % "load_2_percent"
                    obj.sendRead_(obj.servoId_2, obj.SMS_STS_PRESENT_LOAD_L, uint8(2));
                case 6 % "setConsistently_2"
                    % software-only channel; no bus read needed
                otherwise
                    error("ST3215HS:UnknownChannelIndex", "Unknown channelIndex %d.", channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1 % "position_1_deg"
                    getValues = obj.readPositionDeg_(obj.servoId_1);
                case 2 % "load_1_percent"
                    getValues = obj.readLoad_(obj.servoId_1);
                case 3 % "setConsistently_1"
                    getValues = double(obj.useSetPositionConsistent_1);
                case 4 % "position_2_deg"
                    getValues = obj.readPositionDeg_(obj.servoId_2);
                case 5 % "load_2_percent"
                    getValues = obj.readLoad_(obj.servoId_2);
                case 6 % "setConsistently_2"
                    getValues = double(obj.useSetPositionConsistent_2);
                otherwise
                    error("ST3215HS:UnknownChannelIndex", "Unknown channelIndex %d.", channelIndex);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % "position_1_deg"
                    if obj.useSetPositionConsistent_1 && ~obj.bypassConsistentPositionSet_
                        obj.setPositionConsistent(setValues(1), 1);
                    else
                        obj.writePositionDeg_(obj.servoId_1, setValues(1), obj.softMin_1_deg, obj.softMax_1_deg);
                    end
                case 3 % "setConsistently_1"
                    v = setValues(1);
                    if ~(v == 0 || v == 1)
                        error("ST3215HS:InvalidSetConsistentlyChannelValue", ...
                            "setConsistently_1 must be 0 or 1. Received %s.", formattedDisplayText(v));
                    end
                    obj.useSetPositionConsistent_1 = logical(v);
                case 4 % "position_2_deg"
                    if obj.useSetPositionConsistent_2 && ~obj.bypassConsistentPositionSet_
                        obj.setPositionConsistent(setValues(1), 2);
                    else
                        obj.writePositionDeg_(obj.servoId_2, setValues(1), obj.softMin_2_deg, obj.softMax_2_deg);
                    end
                case 6 % "setConsistently_2"
                    v = setValues(1);
                    if ~(v == 0 || v == 1)
                        error("ST3215HS:InvalidSetConsistentlyChannelValue", ...
                            "setConsistently_2 must be 0 or 1. Received %s.", formattedDisplayText(v));
                    end
                    obj.useSetPositionConsistent_2 = logical(v);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case {3, 6} % "setConsistently_1" / "setConsistently_2"
                    TF = true;
                case {1, 4} % "position_1_deg" / "position_2_deg"
                    % Settled-ness check (no target comparison):
                    % Read two consecutive position samples and consider the
                    % servo settled if the quantized tick is unchanged.
                    %
                    % Note: instrumentInterface.setChannel() already polls
                    % setCheckChannel() with a user-configurable setInterval.
                    % This helper should remain a "single-shot" check.
                    %
                    % channelLastSetValues is intentionally unused here.
                    %#ok<NASGU>

                    ticksPerRev = round(360 * obj.ticksPerDegree); % should be 4096

                    aDeg = mod(obj.getChannelByIndex(channelIndex), 360);
                    aTick = mod(round(aDeg(1) * obj.ticksPerDegree), ticksPerRev);
                    if obj.setCheckInterReadDelay_s > 0
                        pause(obj.setCheckInterReadDelay_s);
                    end
                    bDeg = mod(obj.getChannelByIndex(channelIndex), 360);
                    bTick = mod(round(bDeg(1) * obj.ticksPerDegree), ticksPerRev);

                    % aTick/bTick are expected to be integer-valued (after round),
                    % but keep a tiny float-tolerant compare for robustness.
                    TF = abs(double(bTick) - double(aTick)) < 1;
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end
    end

    methods (Access = private)
        function sendPing_(obj, id)
            % Mirrors SCS::Ping transmit framing (no MemAddr byte on-wire).
            id = uint8(id);
            len = uint8(2);
            checksum = bitcmp(uint8(mod(uint16(id) + uint16(len) + uint16(obj.INST_PING), 256)));
            pkt = [uint8(255), uint8(255), id, len, obj.INST_PING, checksum];
            write(obj.communicationHandle, pkt, "uint8");
        end

        function readAckAllowErr_(obj, expectedId)
            % Like readAck_, but does NOT error on nonzero ERR byte (presence-only).
            expectedId = uint8(expectedId);
            if expectedId == uint8(254)
                return;
            end

            obj.checkHead_();
            hdr = read(obj.communicationHandle, 4, "uint8");
            if numel(hdr) ~= 4
                error("ST3215HS:AckTimeout", ...
                    "Servo ACK timeout (expected 4 bytes after header) for expectedId=%d.", double(expectedId));
            end

            id = hdr(1);
            len = hdr(2);
            err = hdr(3);
            chk = hdr(4);

            if id ~= expectedId
                error("ST3215HS:AckIdMismatch", ...
                    "Servo ACK ID mismatch. Expected %d, got %d.", double(expectedId), double(id));
            end
            if len ~= uint8(2)
                error("ST3215HS:AckLenMismatch", ...
                    "Servo ACK length mismatch. Expected 2, got %d.", double(len));
            end

            cal = bitcmp(uint8(mod(uint16(id) + uint16(len) + uint16(err), 256)));
            if cal ~= chk
                error("ST3215HS:AckChecksumMismatch", ...
                    "Servo ACK checksum mismatch.");
            end
        end

        function sendWrite_(obj, id, memAddr, payload)
            obj.sendPacket_(id, obj.INST_WRITE, memAddr, payload);
        end

        function sendRead_(obj, id, memAddr, nLen)
            obj.sendPacket_(id, obj.INST_READ, memAddr, uint8(nLen));
        end

        function sendPacket_(obj, id, inst, memAddr, payload)
            % Mirrors SCS::writeBuf() + {genWrite, Read} in temp/waveshare servo/.../SCS.cpp
            id = uint8(id);
            inst = uint8(inst);
            memAddr = uint8(memAddr);
            payload = uint8(payload);

            % LEN = (number of params) + 2. Params = [memAddr, payload...]
            msgLen = uint8(2 + 1 + numel(payload));

            checksum = uint16(id) + uint16(msgLen) + uint16(inst) + uint16(memAddr) + sum(uint16(payload));
            checksumByte = bitcmp(uint8(mod(checksum, 256)));

            pkt = [uint8(255), uint8(255), id, msgLen, inst, memAddr, payload(:).', checksumByte];
            write(obj.communicationHandle, pkt, "uint8");
        end

        function readAck_(obj, expectedId)
            % Mirrors SCS::Ack()
            expectedId = uint8(expectedId);
            if expectedId == uint8(254)
                return; % broadcast doesn't respond
            end

            obj.checkHead_();
            hdr = read(obj.communicationHandle, 4, "uint8");
            if numel(hdr) ~= 4
                error("ST3215HS:AckTimeout", ...
                    "Servo ACK timeout (expected 4 bytes after header) for expectedId=%d.", double(expectedId));
            end

            id = hdr(1);
            len = hdr(2);
            err = hdr(3);
            chk = hdr(4);

            if id ~= expectedId
                error("ST3215HS:AckIdMismatch", ...
                    "Servo ACK ID mismatch. Expected %d, got %d.", double(expectedId), double(id));
            end
            if len ~= uint8(2)
                error("ST3215HS:AckLenMismatch", ...
                    "Servo ACK length mismatch. Expected 2, got %d.", double(len));
            end

            cal = bitcmp(uint8(mod(uint16(id) + uint16(len) + uint16(err), 256)));
            if cal ~= chk
                error("ST3215HS:AckChecksumMismatch", ...
                    "Servo ACK checksum mismatch.");
            end
            if err ~= 0
                error("ST3215HS:AckErrorStatus", ...
                    "Servo returned error status 0x%s on ACK.", upper(dec2hex(double(err), 2)));
            end
        end

        function data = readResponseData_(obj, expectedId, expectedDataLen)
            % Mirrors SCS::Read() receive side
            expectedId = uint8(expectedId);
            expectedDataLen = double(expectedDataLen);

            obj.checkHead_();
            hdr3 = read(obj.communicationHandle, 3, "uint8"); % [ID, LEN, ERR]
            if numel(hdr3) ~= 3
                error("ST3215HS:ReadTimeout", ...
                    "Servo read timeout (expected 3 header bytes after 0xFF 0xFF) for expectedId=%d.", double(expectedId));
            end

            id = hdr3(1);
            len = hdr3(2);
            err = hdr3(3);

            if id ~= expectedId
                error("ST3215HS:ResponseIdMismatch", ...
                    "Servo response ID mismatch. Expected %d, got %d.", double(expectedId), double(id));
            end

            % In this protocol, LEN = dataLen + 2
            expectedLenField = uint8(expectedDataLen + 2);
            if len ~= expectedLenField
                error("ST3215HS:ResponseLenMismatch", ...
                    "Servo response LEN mismatch. Expected %d, got %d.", double(expectedLenField), double(len));
            end

            data = read(obj.communicationHandle, expectedDataLen, "uint8");
            if numel(data) ~= expectedDataLen
                error("ST3215HS:ReadTimeout", ...
                    "Servo response timeout while reading data bytes (expected %d) for expectedId=%d.", ...
                    expectedDataLen, double(expectedId));
            end

            chk = read(obj.communicationHandle, 1, "uint8");
            if numel(chk) ~= 1
                error("ST3215HS:ReadTimeout", ...
                    "Servo response timeout while reading checksum for expectedId=%d.", double(expectedId));
            end

            calSum = uint16(id) + uint16(len) + uint16(err) + sum(uint16(data));
            cal = bitcmp(uint8(mod(calSum, 256)));
            if cal ~= chk
                error("ST3215HS:ResponseChecksumMismatch", ...
                    "Servo response checksum mismatch.");
            end

            if err ~= 0
                error("ST3215HS:ReadErrorStatus", ...
                    "Servo returned error status 0x%s on read.", upper(dec2hex(double(err), 2)));
            end
        end

        function checkHead_(obj)
            % Mirrors SCS::checkHead()
            prev = uint8(0);
            cnt = 0;
            maxHeaderScanBytes = 64;
            while true
                b = read(obj.communicationHandle, 1, "uint8");
                if isempty(b)
                    error("ST3215HS:HeaderTimeout", ...
                        "Servo response timeout while waiting for header 0xFF 0xFF.");
                end
                cur = b(1);
                if cur == uint8(255) && prev == uint8(255)
                    return;
                end
                prev = cur;
                cnt = cnt + 1;
                if cnt > maxHeaderScanBytes
                    error("ST3215HS:HeaderNotFound", ...
                        "Servo response header not found (scanned > %d bytes).", maxHeaderScanBytes);
                end
            end
        end

        function w = bytesToU16Little_(~, lo, hi)
            w = uint16(hi);
            w = bitor(bitshift(w, 8), uint16(lo));
        end

        function [lo, hi] = u16ToBytesLittle_(~, w)
            w = uint16(w);
            lo = uint8(bitand(w, uint16(255)));
            hi = uint8(bitshift(w, -8));
        end

        function posDeg = readPositionDeg_(obj, servoId)
            data = obj.readResponseData_(uint8(servoId), uint8(2));
            posU16 = obj.bytesToU16Little_(data(1), data(2));
            if bitand(posU16, uint16(bitshift(1, 15))) ~= 0
                posTicks = -double(bitand(posU16, uint16(bitcmp(uint16(bitshift(1, 15))))));
            else
                posTicks = double(posU16);
            end
            posDeg = mod(posTicks / obj.ticksPerDegree, 360);
        end

        function loadVal = readLoad_(obj, servoId)
            data = obj.readResponseData_(uint8(servoId), uint8(2));
            loadU16 = obj.bytesToU16Little_(data(1), data(2));
            % SMS_STS.cpp: sign bit is bit 10, magnitude is (typically) 0..1000 where
            % 1000 == 100% max load.
            signBit = uint16(bitshift(1, 10));
            mag = double(bitand(loadU16, uint16(1023))); % keep only bits 0..9
            if bitand(loadU16, signBit) ~= 0
                mag = -mag;
            end
            loadVal = mag / 10; % convert raw 0..1000 -> percent 0..100
        end

        function writePositionDeg_(obj, servoId, angleDeg, softMinDeg, softMaxDeg)
            if ~isfinite(angleDeg)
                error("ST3215HS:InvalidPosition", ...
                    "Servo position (deg) must be finite. Received %s.", formattedDisplayText(angleDeg));
            end
            % This is not a continuous-rotation actuator. Do not silently wrap.
            if angleDeg == 360
                angleDeg = 0;
            end
            if angleDeg < 0 || angleDeg > 360
                error("ST3215HS:InvalidPosition", ...
                    "Servo position (deg) must be within [0, 360]. Received %s.", formattedDisplayText(angleDeg));
            end

            % Treat NaN as "unbounded" to simplify bring-up/testing.
            if isnan(softMinDeg)
                softMinDeg = -Inf;
            end
            if isnan(softMaxDeg)
                softMaxDeg = Inf;
            end
            if angleDeg < softMinDeg || angleDeg > softMaxDeg
                error("ST3215HS:PositionOutsideSoftLimits", ...
                    "Requested %.3f deg is outside soft limits [%.3f, %.3f] deg for servo ID %d.", ...
                    angleDeg, softMinDeg, softMaxDeg, double(servoId));
            end

            rawPos = round(angleDeg * obj.ticksPerDegree);
            if rawPos < 0
                posAbs = uint16(-rawPos);
                posEnc = bitor(posAbs, uint16(bitshift(1, 15)));
            else
                posEnc = uint16(rawPos);
            end

            spdRaw = round(obj.speed * obj.ticksPerDegree);
            accRaw = round(obj.acceleration * obj.ticksPerDegree);

            spd = uint16(max(0, min(double(obj.STS_MAX_SPEED_RAW), spdRaw)));
            acc = uint8(max(0, min(double(obj.STS_MAX_ACC_RAW), accRaw)));

            payload = zeros(1, 7, "uint8");
            payload(1) = acc;
            [posL, posH] = obj.u16ToBytesLittle_(posEnc);
            payload(2) = posL;
            payload(3) = posH;
            payload(4) = uint8(0);
            payload(5) = uint8(0);
            [spdL, spdH] = obj.u16ToBytesLittle_(spd);
            payload(6) = spdL;
            payload(7) = spdH;

            obj.flush();
            obj.sendWrite_(uint8(servoId), obj.SMS_STS_ACC, payload);
            obj.readAck_(uint8(servoId));
        end

        function [softMinDeg, softMaxDeg] = calibrateSoftLimitsForServo_(obj, positionChannel, loadChannel, loadThreshold_percent, verbose)
            % Uses setChannel/getChannel so the instrument's own settling and IO
            % semantics are exercised. Always scans the full tick range in 1-tick
            % increments (0..4095).

            ticksPerRev = round(360 * obj.ticksPerDegree); % should be 4096

            startDeg = mod(obj.getChannel(positionChannel), 360);
            startTick = mod(round(startDeg * obj.ticksPerDegree), ticksPerRev);
            startDeg = startTick / obj.ticksPerDegree; % quantized to a tick

            experimentContext.print("calibrateSoftLimits: %s startTick=%d startDeg=%.3f loadCh=%s threshold=%g %%", ...
                positionChannel, startTick, startDeg, loadChannel, loadThreshold_percent);

            % Defaults: unbounded unless threshold is hit.
            softMinDeg = -Inf;
            softMaxDeg = Inf;

            % --- Scan toward minimum tick (0) ---
            curTick = startTick;
            for nextTick = (startTick - 1):-1:0
                obj.setChannel(positionChannel, nextTick / obj.ticksPerDegree);
                loadVal = obj.getChannel(loadChannel);
                if verbose
                    experimentContext.print("  min-scan: tick=%4d load=%g %%", nextTick, loadVal);
                end
                if abs(loadVal) >= loadThreshold_percent
                    % Set limit to the last safe point BEFORE overload.
                    softMinDeg = curTick / obj.ticksPerDegree;
                    break;
                end
                curTick = nextTick;
            end

            % Return to start before scanning toward max
            obj.setChannel(positionChannel, startDeg);

            % --- Scan toward maximum tick (ticksPerRev-1) ---
            curTick = startTick;
            for nextTick = (startTick + 1):(ticksPerRev - 1)
                obj.setChannel(positionChannel, nextTick / obj.ticksPerDegree);
                loadVal = obj.getChannel(loadChannel);
                if verbose
                    experimentContext.print("  max-scan: tick=%4d load=%g %%", nextTick, loadVal);
                end
                if abs(loadVal) >= loadThreshold_percent
                    % Set limit to the last safe point BEFORE overload.
                    softMaxDeg = curTick / obj.ticksPerDegree;
                    break;
                end
                curTick = nextTick;
            end

            % Return to start after scanning to avoid leaving the servo at an endpoint.
            obj.setChannel(positionChannel, startDeg);

            if isfinite(softMinDeg)
                softMinTick = round(softMinDeg * obj.ticksPerDegree);
            else
                softMinTick = NaN;
            end
            if isfinite(softMaxDeg)
                softMaxTick = round(softMaxDeg * obj.ticksPerDegree);
            else
                softMaxTick = NaN;
            end
            experimentContext.print("calibrateSoftLimits: %s result: soft limits=[%.3f, %.3f] deg ticks=[%g, %g]", ...
                positionChannel, softMinDeg, softMaxDeg, softMinTick, softMaxTick);
        end

        function restoreRequireSetCheck_(obj, prevValue)
            obj.requireSetCheck = prevValue;
        end

        function restoreBypassConsistentPositionSet_(obj, prevValue)
            obj.bypassConsistentPositionSet_ = prevValue;
        end
    end

    methods (Static, Access = private)
        function opts = parseConstructorArgs_(varargin)
            % parseConstructorArgs_ Parse constructor name/value args.
            % servoId_2 intentionally has NO default: it is only present if the user supplied it.

            opts = struct();
            opts.servoId_1 = 1;
            opts.baudRate = 1000000;
            opts.timeoutSeconds = 0.2;

            if mod(nargin, 2) ~= 0
                error("ST3215HS:InvalidConstructorArgs", ...
                    "Constructor name/value arguments must come in pairs. Received %d trailing values.", nargin);
            end

            k = 1;
            while k <= nargin
                nameRaw = varargin{k};
                value = varargin{k + 1};

                if ~(isstring(nameRaw) && isscalar(nameRaw)) && ~(ischar(nameRaw) && isrow(nameRaw))
                    error("ST3215HS:InvalidConstructorArgs", ...
                        "Name/value argument names must be string scalars or character vectors.");
                end
                name = lower(string(nameRaw));

                switch name
                    case "servoid_1"
                        opts.servoId_1 = instrument_ST3215HS.requireIntegerScalar_(value, "servoId_1");
                    case "servoid_2"
                        % Only set if the user explicitly provided it.
                        opts.servoId_2 = instrument_ST3215HS.requireIntegerScalar_(value, "servoId_2");
                    case "baudrate"
                        v = instrument_ST3215HS.requireIntegerScalar_(value, "baudRate");
                        if v <= 0
                            error("ST3215HS:InvalidConstructorArgs", "baudRate must be a positive integer.");
                        end
                        opts.baudRate = v;
                    case "timeoutseconds"
                        if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
                            error("ST3215HS:InvalidConstructorArgs", ...
                                "timeoutSeconds must be a positive, finite scalar.");
                        end
                        opts.timeoutSeconds = double(value);
                    otherwise
                        error("ST3215HS:InvalidConstructorArgs", ...
                            "Unknown name/value argument '%s'.", nameRaw);
                end

                k = k + 2;
            end
        end

        function v = requireIntegerScalar_(v, argName)
            if ~(isnumeric(v) && isscalar(v) && isfinite(v) && floor(v) == v)
                error("ST3215HS:InvalidConstructorArgs", ...
                    "%s must be an integer, finite scalar. Received %s.", argName, formattedDisplayText(v));
            end
            v = double(v);
        end

        function servoId = validateServoIdOrError_(servoId, argName)
            % validateServoIdOrError_ Enforce official ID range 0..253.
            % 254 is broadcast (no response); 255 is reserved/invalid.
            if ~isfinite(servoId) || ~isscalar(servoId) || floor(servoId) ~= servoId
                error("ST3215HS:InvalidServoId", ...
                    "%s must be an integer scalar in the range 0..253. Received %s.", ...
                    argName, formattedDisplayText(servoId));
            end
            if servoId < 0 || servoId > 253
                error("ST3215HS:InvalidServoId", ...
                    "%s must be an integer in the range 0..253. Received %d.", ...
                    argName, servoId);
            end
        end
    end
end


