classdef virtualInstrument_hysteresis < virtualInstrumentInterface
    % virtualInstrument_hysteresis - Map normalized inputs to a point1->point2->point1 setpoint.
    %
    % Uses a single virtual channel ("hysteresis") that accepts normalized
    % values in [0, 1]. The target hardware channel designated by
    % setChannelName is driven such that:
    %   * 0   -> point1
    %   * 0.5 -> point2
    %   * 1   -> point1
    % Intermediate inputs are piecewise-linear between these anchors.
    %
    % Thomas 20251113

    properties
        setChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_tg";
        point1 (1, 1) double {mustBeFinite};
        point2 (1, 1) double {mustBeFinite};
    end

    methods

        function obj = virtualInstrument_hysteresis(address, masterRackProxy, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRackProxy (1, 1) instrumentRackProxy;
                NameValueArgs.setChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_tg";
                NameValueArgs.point1 (1, 1) double {mustBeFinite};
                NameValueArgs.point2 (1, 1) double {mustBeFinite};
            end

            obj@virtualInstrumentInterface(address, masterRackProxy);
            obj.requireSetCheck = true;

            obj.setChannelName = NameValueArgs.setChannelName;
            obj.point1 = NameValueArgs.point1;
            obj.point2 = NameValueArgs.point2;

            obj.addChannel("hysteresis");
        end

    end

    methods (Access = ?instrumentInterface)

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    normalizedInput = setValues(1);
                    obj.validateNormalizedInput(normalizedInput);
                    setTarget = obj.computeSetTarget(normalizedInput);

                    masterRackProxy = obj.getMasterRackProxy();
                    masterRackProxy.rackSetWrite(obj.setChannelName, setTarget);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            switch channelIndex
                case 1
                    masterRackProxy = obj.getMasterRackProxy();
                    TF = masterRackProxy.rackSetCheck(obj.setChannelName);
            end
        end

        function getValues = getReadChannelHelper(~, channelIndex)
            getValues = [];
            switch channelIndex
                case 1
                    error("virtualInstrument_hysteresis:GetUnsupported", ...
                        "Hysteresis channel is write-only; inverse map is not single valued.");
            end
        end

    end

    methods (Access = private)

        function validateNormalizedInput(~, normalizedInput)
            if ~isfinite(normalizedInput)
                error("virtualInstrument_hysteresis:NonFiniteInput", ...
                    "Hysteresis channel input must be finite.");
            end
            if normalizedInput < 0 || normalizedInput > 1
                error("virtualInstrument_hysteresis:InputOutOfRange", ...
                    "Hysteresis channel input must be within [0, 1]. Received %g.", normalizedInput);
            end
        end

        function setTarget = computeSetTarget(obj, normalizedInput)
            span = obj.point2 - obj.point1;
            if normalizedInput <= 0.5
                weight = normalizedInput / 0.5; % maps [0, 0.5] -> [0, 1]
                setTarget = obj.point1 + weight * span;
            else
                weight = (normalizedInput - 0.5) / 0.5; % maps (0.5, 1] -> [0, 1]
                setTarget = obj.point2 - weight * span;
            end
        end

    end

end



