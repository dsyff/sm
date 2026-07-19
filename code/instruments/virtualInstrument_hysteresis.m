classdef virtualInstrument_hysteresis < virtualInstrumentInterface
    % virtualInstrument_hysteresis - Map hysteresis inputs to a point1->point2->point1 setpoint.
    %
    % Uses a single virtual channel ("hysteresis") that accepts values in
    % [-0.25, 1.25]. The target hardware channel designated by
    % setChannelName is driven such that:
    %   * -0.25 -> 0 when point1..point2 includes 0; otherwise point1
    %   * 0   -> point1
    %   * 0.5 -> point2
    %   * 1   -> point1
    %   * 1.25 -> 0 when point1..point2 includes 0; otherwise point1
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
                    hysteresisInput = setValues(1);
                    obj.validateInput(hysteresisInput);
                    setTarget = obj.computeSetTarget(hysteresisInput);

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

        function validateInput(~, hysteresisInput)
            if ~isfinite(hysteresisInput)
                error("virtualInstrument_hysteresis:NonFiniteInput", ...
                    "Hysteresis channel input must be finite.");
            end
            if hysteresisInput < -0.25 || hysteresisInput > 1.25
                error("virtualInstrument_hysteresis:InputOutOfRange", ...
                    "Hysteresis channel input must be within [-0.25, 1.25]. Received %g.", hysteresisInput);
            end
        end

        function setTarget = computeSetTarget(obj, hysteresisInput)
            outerTarget = obj.point1;
            if min(obj.point1, obj.point2) <= 0 && max(obj.point1, obj.point2) >= 0
                outerTarget = 0;
            end
            setTarget = interp1( ...
                [-0.25, 0, 0.5, 1, 1.25], ...
                [outerTarget, obj.point1, obj.point2, obj.point1, outerTarget], ...
                hysteresisInput);
        end

    end

end



