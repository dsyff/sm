classdef virtualInstrument_hysteresis < virtualInstrumentInterface
    % virtualInstrument_hysteresis - Map normalized inputs to a min→max→min setpoint.
    %
    % Uses a single virtual channel ("hysteresis") that accepts normalized
    % values in [0, 1]. The target hardware channel designated by
    % setChannelName is driven such that:
    %   * 0   -> min
    %   * 0.5 -> max
    %   * 1   -> min
    % Intermediate inputs are piecewise-linear between these anchors.
    %
    % Thomas 20251113

    properties
        setChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_tg";
        min (1, 1) double {mustBeFinite};
        max (1, 1) double {mustBeFinite};
    end

    methods

        function obj = virtualInstrument_hysteresis(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack;
                NameValueArgs.setChannelName (1, 1) string {mustBeNonzeroLengthText} = "V_tg";
                NameValueArgs.min (1, 1) double {mustBeFinite};
                NameValueArgs.max (1, 1) double {mustBeFinite};
            end

            obj@virtualInstrumentInterface(address, masterRack);
            obj.requireSetCheck = true;

            obj.setChannelName = NameValueArgs.setChannelName;
            obj.min = NameValueArgs.min;
            obj.max = NameValueArgs.max;
            obj.validateRange();

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

                    rack = obj.getMasterRack();
                    rack.rackSetWrite(obj.setChannelName, setTarget);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    TF = rack.rackSetCheck(obj.setChannelName);
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
            span = obj.max - obj.min;
            if normalizedInput <= 0.5
                weight = normalizedInput / 0.5; % maps [0, 0.5] -> [0, 1]
                setTarget = obj.min + weight * span;
            else
                weight = (normalizedInput - 0.5) / 0.5; % maps (0.5, 1] -> [0, 1]
                setTarget = obj.max - weight * span;
            end
        end

        function validateRange(obj)
            if ~(obj.max > obj.min)
                error("virtualInstrument_hysteresis:InvalidRange", ...
                    "max must be greater than min. Received %g and %g.", obj.max, obj.min);
            end
        end

    end

end



