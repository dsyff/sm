classdef virtualInstrument_nE < virtualInstrumentInterface
    % virtualInstrument_nE - Fixed version with consistent matrix mapping.
    % Thomas 20251120 (revised 20260116)

    properties
        vTgChannelName (1, 1) string
        vBgChannelName (1, 1) string
        vTgLimits (1, 2) double {mustBeFinite}
        vBgLimits (1, 2) double {mustBeFinite}

        vTg_n0E0 (1, 1) double {mustBeFinite}
        vBg_n0E0 (1, 1) double {mustBeFinite}
        vTg_n0ENot0 (1, 1) double {mustBeFinite}
        vBg_n0ENot0 (1, 1) double {mustBeFinite}

        nStored (1, 1) double {mustBeFinite} = 0
        EStored (1, 1) double {mustBeFinite} = 0

        % When true: if the n/E target maps outside gate limits, skip setting.
        % When false (default): clamp gate voltages to limits and set anyway.
        skipOutOfBounds (1, 1) logical = false
    end

    properties (Access = private)
        % M is the 2x2 matrix such that [dVtg; dVbg] = M * [nRaw; ERaw]
        M (2, 2) double
        Minv (2, 2) double
        nMin (1, 1) double
        nSpan (1, 1) double
        EMin (1, 1) double
        ESpan (1, 1) double
    end

    methods
        function obj = virtualInstrument_nE(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string
                masterRack (1, 1) instrumentRack
                NameValueArgs.vBgChannelName (1, 1) string
                NameValueArgs.vTgChannelName (1, 1) string
                NameValueArgs.vBgLimits (1, 2) double
                NameValueArgs.vTgLimits (1, 2) double
                NameValueArgs.vBg_n0E0 (1, 1) double
                NameValueArgs.vTg_n0E0 (1, 1) double
                NameValueArgs.vBg_n0ENot0 (1, 1) double
                NameValueArgs.vTg_n0ENot0 (1, 1) double
            end

            obj@virtualInstrumentInterface(address, masterRack);

            obj.vTgChannelName = NameValueArgs.vTgChannelName;
            obj.vBgChannelName = NameValueArgs.vBgChannelName;
            
            % Restore helper methods for constructor
            obj.vTgLimits = obj.sortLimits(NameValueArgs.vTgLimits, "vTgLimits");
            obj.vBgLimits = obj.sortLimits(NameValueArgs.vBgLimits, "vBgLimits");
            obj.vTg_n0E0 = NameValueArgs.vTg_n0E0;
            obj.vBg_n0E0 = NameValueArgs.vBg_n0E0;
            obj.vTg_n0ENot0 = NameValueArgs.vTg_n0ENot0;
            obj.vBg_n0ENot0 = NameValueArgs.vBg_n0ENot0;

            obj.validateCalibrationPoints();
            obj.computeTransformationMatrix();

            obj.addChannel("n", setTolerances = 1E-3);
            obj.addChannel("E", setTolerances = 1E-3);
            obj.addChannel("nE_within_bounds");
            obj.addChannel("skipOutOfBounds");

            obj.initializeStoredStateFromHardware();
        end
    end

    methods (Access = ?instrumentInterface)
        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % n
                    obj.nStored = setValues(1);
                case 2 % E
                    obj.EStored = setValues(1);
                case 4 % skipOutOfBounds
                    v = setValues(1);
                    if ~(v == 0 || v == 1)
                        error("virtualInstrument_nE:InvalidSkipSetting", "skipOutOfBounds must be 0 or 1.");
                    end
                    obj.skipOutOfBounds = logical(v);
                otherwise
                    setWriteChannelHelper@virtualInstrumentInterface(obj, channelIndex, setValues);
            end
            obj.setHardwareFromState();
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case {1, 2}
                    rack = obj.getMasterRack();
                    gateValues = rack.rackGet([obj.vTgChannelName, obj.vBgChannelName]);
                    [n, E] = obj.computeNormalizedStateFromVoltages(gateValues(1), gateValues(2));
                    if channelIndex == 1
                        getValues = n;
                    else
                        getValues = E;
                    end
                case 3
                    [~, ~, withinBounds] = obj.computeGateVoltages(obj.nStored, obj.EStored);
                    getValues = double(withinBounds);
                case 4
                    getValues = double(obj.skipOutOfBounds);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            if channelIndex == 4
                TF = true;
                return;
            end
            [vtg, vbg, withinBounds] = obj.computeGateVoltages(obj.nStored, obj.EStored);
            if ~withinBounds && obj.skipOutOfBounds
                TF = true;
                return;
            end
            [nEff, EEff] = obj.computeNormalizedStateFromVoltages(vtg, vbg);
            expected = [nEff, EEff];
            channel = obj.channelTable.channels(channelIndex);
            getValues = obj.getChannel(channel);
            TF = all(abs(getValues - expected(channelIndex)) <= obj.setTolerances{channelIndex});
        end
    end

    methods (Access = private)
        function computeTransformationMatrix(obj)
            % Determine r from the slope of n=0 (E-axis)
            dVtg_E = obj.vTg_n0ENot0 - obj.vTg_n0E0;
            dVbg_E = obj.vBg_n0ENot0 - obj.vBg_n0E0;
            r = -dVtg_E / dVbg_E; 

            % Use the calibration point to set the E-axis scale.
            alphaE = 1;
            alphaN = 1;

            % Build Matrix M: [dVtg; dVbg] = M * [nRaw; ERaw]
            obj.M = [0.5*r*alphaN,  0.5*r*alphaE; 
                     0.5*alphaN,   -0.5*alphaE];
            
            obj.Minv = inv(obj.M);

            vtgCorners = [obj.vTgLimits(1), obj.vTgLimits(1), obj.vTgLimits(2), obj.vTgLimits(2)];
            vbgCorners = [obj.vBgLimits(1), obj.vBgLimits(2), obj.vBgLimits(1), obj.vBgLimits(2)];
            dV = [vtgCorners - obj.vTg_n0E0; vbgCorners - obj.vBg_n0E0];
            raw = obj.Minv * dV;
            obj.nMin = min(raw(1, :));
            obj.nSpan = max(raw(1, :)) - obj.nMin;
            obj.EMin = min(raw(2, :));
            obj.ESpan = max(raw(2, :)) - obj.EMin;
            if obj.nSpan == 0 || obj.ESpan == 0
                error("virtualInstrument_nE:ZeroSpanRange", "Gate limits produce zero span in n or E.");
            end
        end

        function [vtg, vbg, withinBounds] = computeGateVoltages(obj, n, E)
            nRaw = obj.nMin + n * obj.nSpan;
            ERaw = obj.EMin + E * obj.ESpan;
            delta = obj.M * [nRaw; ERaw];
            vtg = obj.vTg_n0E0 + delta(1);
            vbg = obj.vBg_n0E0 + delta(2);
            withinBounds = vtg >= obj.vTgLimits(1) && vtg <= obj.vTgLimits(2) && ...
                vbg >= obj.vBgLimits(1) && vbg <= obj.vBgLimits(2);
            vtg = min(max(vtg, obj.vTgLimits(1)), obj.vTgLimits(2));
            vbg = min(max(vbg, obj.vBgLimits(1)), obj.vBgLimits(2));
        end

        function [n, E] = computeNormalizedStateFromVoltages(obj, vtg, vbg)
            dV = [vtg - obj.vTg_n0E0; vbg - obj.vBg_n0E0];
            raw = obj.Minv * dV;
            n = (raw(1) - obj.nMin) / obj.nSpan;
            E = (raw(2) - obj.EMin) / obj.ESpan;
            n = min(max(n, 0), 1);
            E = min(max(E, 0), 1);
        end

        function scale = calculateMaxScale(obj, aTg, aBg, preferredSign)
            int = obj.intersectInterval([-Inf, Inf], obj.intervalFromAffineBounds(aTg, obj.vTg_n0E0, obj.vTgLimits));
            int = obj.intersectInterval(int, obj.intervalFromAffineBounds(aBg, obj.vBg_n0E0, obj.vBgLimits));
            
            candidates = int(sign(int) == preferredSign | int == 0);
            [~, idx] = max(abs(candidates));
            scale = candidates(idx);
            if scale == 0, error("virtualInstrument_nE:NoFeasibleScale", "Range is zero."); end
        end

        function alphaN = calculateMaxScaleN(obj, r, alphaE)
            int = [-Inf, Inf];
            int = obj.intersectInterval(int, obj.intervalFromAffineBounds(0.5*r, obj.vTg_n0E0, obj.vTgLimits));
            int = obj.intersectInterval(int, obj.intervalFromAffineBounds(0.5, obj.vBg_n0E0, obj.vBgLimits));
            int = obj.intersectInterval(int, obj.intervalFromAffineBounds(0.5*r, obj.vTg_n0E0 + 0.5*r*alphaE, obj.vTgLimits));
            int = obj.intersectInterval(int, obj.intervalFromAffineBounds(0.5, obj.vBg_n0E0 - 0.5*alphaE, obj.vBgLimits));
            [~, idx] = max(abs(int));
            alphaN = int(idx);
        end
        
        function setHardwareFromState(obj)
            [vtg, vbg, withinBounds] = obj.computeGateVoltages(obj.nStored, obj.EStored);
            if ~withinBounds && obj.skipOutOfBounds
                return;
            end
            rack = obj.getMasterRack();
            rack.rackSetWrite([obj.vTgChannelName, obj.vBgChannelName], [vtg; vbg]);
        end

        function initializeStoredStateFromHardware(obj)
            rack = obj.getMasterRack();
            gateValues = rack.rackGet([obj.vTgChannelName, obj.vBgChannelName]);
            [n, E] = obj.computeNormalizedStateFromVoltages(gateValues(1), gateValues(2));
            obj.nStored = n;
            obj.EStored = E;
        end


        function validateCalibrationPoints(obj)
            if obj.vTg_n0E0 < obj.vTgLimits(1) || obj.vTg_n0E0 > obj.vTgLimits(2) || ...
               obj.vBg_n0E0 < obj.vBgLimits(1) || obj.vBg_n0E0 > obj.vBgLimits(2)
                error("virtualInstrument_nE:OriginOutOfLimits", "Origin point outside limits.");
            end
            if obj.vBg_n0ENot0 == obj.vBg_n0E0
                error("virtualInstrument_nE:DegenerateCalibration", "Calibration requires ΔVbg != 0.");
            end
        end

        function interval = intervalFromAffineBounds(~, a, b, limits)
            if a == 0
                if b < limits(1) || b > limits(2), interval = [Inf, -Inf];
                else, interval = [-Inf, Inf]; end
                return;
            end
            x = (limits - b) / a;
            interval = [min(x), max(x)];
        end

        function out = intersectInterval(~, a, b)
            out = [max(a(1), b(1)), min(a(2), b(2))];
        end

        function sorted = sortLimits(~, limits, label)
            sorted = sort(limits);
            if sorted(1) == sorted(2)
                error("virtualInstrument_nE:ZeroSpanLimit", "Limits for %s must span a range.", label);
            end
        end
    end
end