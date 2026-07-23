classdef virtualInstrument_gate < virtualInstrumentInterface
    % Protected gate wrapper around raw Keithley voltage/current channels.
    % After smready, change live limits on the engine worker with, for example:
    %   smset("virtual_gate_tg", "currentMin", -1.5E-9)
    %   smset("virtual_gate_tg", "currentMax", 1.5E-9)
    %   smset("virtual_gate_tg", "occurrence", 3)
    % A current-limit sequence only advances while successive SET voltages
    % increase strictly in absolute value.
    properties
        currentMin (1, 1) double = -1.5E-9
        currentMax (1, 1) double = 1.5E-9
        occurrence (1, 1) double {mustBeInteger, mustBeGreaterThanOrEqual(occurrence, 2)} = 3
    end

    properties (SetAccess = immutable)
        voltageChannelName (1, 1) string
        currentChannelName (1, 1) string
        viChannelName (1, 1) string
    end

    properties (Access = private)
        consecutiveLimitCount (1, 1) double = 0
        latestSetVoltage (1, 1) double = NaN
        previousLimitVoltage (1, 1) double = NaN
    end

    methods
        function obj = virtualInstrument_gate(address, masterRackProxy, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                masterRackProxy (1, 1) instrumentRackProxy
                NameValueArgs.voltageChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.currentChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.viChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.currentMin (1, 1) double = -1.5E-9
                NameValueArgs.currentMax (1, 1) double = 1.5E-9
                NameValueArgs.occurrence (1, 1) double ...
                    {mustBeInteger, mustBeGreaterThanOrEqual(NameValueArgs.occurrence, 2)} = 3
            end

            obj@virtualInstrumentInterface(address, masterRackProxy);
            obj.voltageChannelName = NameValueArgs.voltageChannelName;
            obj.currentChannelName = NameValueArgs.currentChannelName;
            obj.viChannelName = NameValueArgs.viChannelName;
            obj.currentMin = NameValueArgs.currentMin;
            obj.currentMax = NameValueArgs.currentMax;
            obj.occurrence = NameValueArgs.occurrence;
            masterRackProxy.assertChannelsExist([obj.voltageChannelName, obj.currentChannelName, obj.viChannelName]);

            obj.addChannel("voltage");
            obj.addChannel("current");
            obj.addChannel("VI", 2);
        end
    end

    methods (Access = ?instrumentInterface)
        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex ~= 1
                error("virtualInstrument_gate:SetUnsupported", "Only the voltage channel is settable.");
            end
            obj.getMasterRackProxy().rackSetWrite(obj.voltageChannelName, setValues);
            obj.latestSetVoltage = setValues(1);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            proxy = obj.getMasterRackProxy();
            switch channelIndex
                case 1
                    getValues = proxy.rackGet(obj.voltageChannelName);
                case 2
                    getValues = proxy.rackGet(obj.currentChannelName);
                    obj.checkCurrent_(getValues(1));
                case 3
                    getValues = proxy.rackGet(obj.viChannelName);
                    obj.checkCurrent_(getValues(2));
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            if channelIndex == 1
                TF = obj.getMasterRackProxy().rackSetCheck(obj.voltageChannelName);
            else
                TF = true;
            end
        end
    end

    methods (Access = private)
        function checkCurrent_(obj, current)
            if obj.currentMin > obj.currentMax
                error("virtualInstrument_gate:InvalidCurrentLimits", ...
                    "currentMin must not exceed currentMax.");
            end
            if current >= obj.currentMin && current <= obj.currentMax
                obj.resetLimitSequence_();
                return;
            end

            voltage = obj.latestSetVoltage;
            if ~isfinite(voltage)
                obj.resetLimitSequence_();
                return;
            end
            if obj.consecutiveLimitCount == 0 || abs(voltage) > abs(obj.previousLimitVoltage)
                obj.consecutiveLimitCount = obj.consecutiveLimitCount + 1;
            else
                obj.consecutiveLimitCount = 1;
            end
            obj.previousLimitVoltage = voltage;
            if obj.consecutiveLimitCount < obj.occurrence
                return;
            end

            obj.resetLimitSequence_();
            obj.getMasterRackProxy().rackSetWriteImmediate(obj.voltageChannelName, 0);
            obj.latestSetVoltage = 0;
            experimentContext.requestScanStop(sprintf( ...
                "%s current limit triggered: %.6g A is outside [%.6g, %.6g] A for %d consecutive reads while |SET voltage| increased; latest SET voltage was %.6g V and was set to zero.", ...
                obj.address, current, obj.currentMin, obj.currentMax, obj.occurrence, voltage));
        end

        function resetLimitSequence_(obj)
            obj.consecutiveLimitCount = 0;
            obj.previousLimitVoltage = NaN;
        end
    end
end
