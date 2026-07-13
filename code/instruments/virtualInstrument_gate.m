classdef virtualInstrument_gate < virtualInstrumentInterface
    properties
        currentMin (1, 1) double = -inf
        currentMax (1, 1) double = inf
        occurrence (1, 1) double {mustBePositive, mustBeInteger} = 3
    end

    properties (SetAccess = immutable)
        voltageChannelName (1, 1) string
        currentChannelName (1, 1) string
        viChannelName (1, 1) string
    end

    properties (Access = private)
        consecutiveLimitCount (1, 1) double = 0
    end

    methods
        function obj = virtualInstrument_gate(address, masterRackProxy, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                masterRackProxy (1, 1) instrumentRackProxy
                NameValueArgs.voltageChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.currentChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.viChannelName (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.currentMin (1, 1) double = -inf
                NameValueArgs.currentMax (1, 1) double = inf
                NameValueArgs.occurrence (1, 1) double {mustBePositive, mustBeInteger} = 3
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
                obj.consecutiveLimitCount = 0;
                return;
            end

            obj.consecutiveLimitCount = obj.consecutiveLimitCount + 1;
            if obj.consecutiveLimitCount < obj.occurrence
                return;
            end

            obj.consecutiveLimitCount = 0;
            obj.getMasterRackProxy().rackSetWriteImmediate(obj.voltageChannelName, 0);
            experimentContext.requestScanStop(sprintf( ...
                "%s current limit triggered: %.6g A is outside [%.6g, %.6g] A for %d consecutive reads; voltage was set to zero.", ...
                obj.address, current, obj.currentMin, obj.currentMax, obj.occurrence));
        end
    end
end
