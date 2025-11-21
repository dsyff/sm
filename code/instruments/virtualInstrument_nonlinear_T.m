classdef virtualInstrument_nonlinear_T < virtualInstrumentInterface
    % virtualInstrument_nonlinear_T - Map normalized inputs to a nonlinear temperature span.
    %
    % Exposes a single virtual write channel ("nonlinear_T") whose values
    % lie in [0, 1]. Each write maps the normalized value x to a temperature
    % target f(x) inside [T_min, T_max] using the reciprocal-linear formula:
    %
    %   f(x) = 1 / ((1/T_max - 1/T_min) * x + 1/T_min)
    %
    % Evenly spaced inputs in x therefore become evenly spaced in 1/f(x),
    % which densifies points near T_min while still reaching T_max at x = 1.
    %
    % Thomas 20251114
    %

    properties
        tSetChannelName (1, 1) string;
        tMin (1, 1) double {mustBeFinite, mustBePositive} = 4;
        tMax (1, 1) double {mustBeFinite, mustBePositive} = 200;
    end

    methods

        function obj = virtualInstrument_nonlinear_T(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack;
                NameValueArgs.tSetChannelName (1, 1) string;
                NameValueArgs.tMin (1, 1) double {mustBeFinite, mustBePositive} = 4;
                NameValueArgs.tMax (1, 1) double {mustBeFinite, mustBePositive} = 200;
            end

            obj@virtualInstrumentInterface(address, masterRack);
            obj.requireSetCheck = true;

            obj.tSetChannelName = NameValueArgs.tSetChannelName;
            obj.tMin = NameValueArgs.tMin;
            obj.tMax = NameValueArgs.tMax;

            obj.addChannel("nonlinear_T");
        end

    end

    methods (Access = ?instrumentInterface)

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    normalizedInput = setValues(1);
                    obj.validateNormalizedInput(normalizedInput);

                    setTarget = obj.mapNormalizedToTemperature(normalizedInput);
                    rack = obj.getMasterRack();
                    rack.rackSetWrite(obj.tSetChannelName, setTarget);
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    TF = rack.rackSetCheck(obj.tSetChannelName);
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    rack = obj.getMasterRack();
                    temperature = rack.rackGet(obj.tSetChannelName);
                    getValues = obj.mapTemperatureToNormalized(temperature);
            end
        end

    end

    methods (Access = private)

        function validateNormalizedInput(~, normalizedInput)
            if ~isfinite(normalizedInput)
                error("virtualInstrument_nonlinear_T:NonFiniteInput", ...
                    "nonlinear_T channel input must be finite.");
            end
            if normalizedInput < 0 || normalizedInput > 1
                error("virtualInstrument_nonlinear_T:InputOutOfRange", ...
                    "nonlinear_T channel input must be within [0, 1]. Received %g.", normalizedInput);
            end
        end

        function temperature = mapNormalizedToTemperature(obj, normalizedInput)
            reciprocalSlope = (1 / obj.tMax) - (1 / obj.tMin);
            temperature = 1 / (reciprocalSlope * normalizedInput + (1 / obj.tMin));
        end

        function normalizedInput = mapTemperatureToNormalized(obj, temperature)
            reciprocalSlope = (1 / obj.tMax) - (1 / obj.tMin);
            normalizedInput = (1 ./ temperature - (1 / obj.tMin)) ./ reciprocalSlope;
        end

    end

end

