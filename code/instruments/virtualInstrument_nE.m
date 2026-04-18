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

        % Requested normalized state, kept exactly as requested by n/E sets.
        % withinBoundsStored is just an analysis flag for the requested point.
        nStored (1, 1) double {mustBeFinite} = 0
        EStored (1, 1) double {mustBeFinite} = 0
        withinBoundsStored (1, 1) logical = true

        % 0: keep E exact and snap n.
        % 1: keep n exact and snap E.
        nFast0EFast1 (1, 1) logical = false
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
            obj.addChannel("nFast0EFast1");

            obj.initializeStoredStateFromHardware();
        end
    end

    methods (Access = ?instrumentInterface)
        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % n
                    obj.validateNormalizedValue(setValues(1), "n");
                    obj.nStored = setValues(1);
                    [~, ~, obj.withinBoundsStored] = obj.computeGateVoltages(obj.nStored, obj.EStored);
                case 2 % E
                    obj.validateNormalizedValue(setValues(1), "E");
                    obj.EStored = setValues(1);
                    [~, ~, obj.withinBoundsStored] = obj.computeGateVoltages(obj.nStored, obj.EStored);
                case 4 % nFast0EFast1
                    obj.nFast0EFast1 = logical(setValues(1));
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
                    getValues = double(obj.withinBoundsStored);
                case 4
                    getValues = double(obj.nFast0EFast1);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            if channelIndex == 4
                TF = true;
                return;
            end
            [nApplied, EApplied] = obj.resolveAppliedState(obj.nStored, obj.EStored);
            rack = obj.getMasterRack();
            gateValues = rack.rackGet([obj.vTgChannelName, obj.vBgChannelName]);
            [nActual, EActual] = obj.computeNormalizedStateFromVoltages(gateValues(1), gateValues(2));
            actual = [nActual, EActual];
            expected = [nApplied, EApplied];
            tolerances = [obj.setTolerances{1}(1), obj.setTolerances{2}(1)];
            TF = all(abs(actual - expected) <= tolerances);
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
            
            obj.Minv = obj.M \ eye(2);

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
            tol = 1E-12 * max([1, abs(obj.vTgLimits), abs(obj.vBgLimits)]);
            withinBounds = vtg >= obj.vTgLimits(1) - tol && vtg <= obj.vTgLimits(2) + tol && ...
                vbg >= obj.vBgLimits(1) - tol && vbg <= obj.vBgLimits(2) + tol;
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
            [nApplied, EApplied] = obj.resolveAppliedState(obj.nStored, obj.EStored);
            [vtg, vbg] = obj.computeGateVoltages(nApplied, EApplied);
            rack = obj.getMasterRack();
            rack.rackSetWrite([obj.vTgChannelName, obj.vBgChannelName], [vtg; vbg]);
        end

        function initializeStoredStateFromHardware(obj)
            rack = obj.getMasterRack();
            gateValues = rack.rackGet([obj.vTgChannelName, obj.vBgChannelName]);
            [n, E] = obj.computeNormalizedStateFromVoltages(gateValues(1), gateValues(2));
            obj.nStored = n;
            obj.EStored = E;
            [~, ~, obj.withinBoundsStored] = obj.computeGateVoltages(obj.nStored, obj.EStored);
        end

        function [nResolved, EResolved] = resolveAppliedState(obj, nTarget, ETarget)
            nResolved = nTarget;
            EResolved = ETarget;
            if obj.nFast0EFast1
                EResolved = obj.clampToInterval(ETarget, obj.computeFeasibleEInterval(nTarget));
            else
                nResolved = obj.clampToInterval(nTarget, obj.computeFeasibleNInterval(ETarget));
            end
        end

        function interval = computeFeasibleNInterval(obj, E)
            ERaw = obj.EMin + E * obj.ESpan;
            base = [obj.vTg_n0E0; obj.vBg_n0E0] + obj.M * [obj.nMin; ERaw];
            coeff = obj.M(:, 1) * obj.nSpan;
            interval = obj.intersectInterval([0, 1], obj.intervalFromAffineBounds(coeff(1), base(1), obj.vTgLimits));
            interval = obj.intersectInterval(interval, obj.intervalFromAffineBounds(coeff(2), base(2), obj.vBgLimits));
        end

        function interval = computeFeasibleEInterval(obj, n)
            nRaw = obj.nMin + n * obj.nSpan;
            base = [obj.vTg_n0E0; obj.vBg_n0E0] + obj.M * [nRaw; obj.EMin];
            coeff = obj.M(:, 2) * obj.ESpan;
            interval = obj.intersectInterval([0, 1], obj.intervalFromAffineBounds(coeff(1), base(1), obj.vTgLimits));
            interval = obj.intersectInterval(interval, obj.intervalFromAffineBounds(coeff(2), base(2), obj.vBgLimits));
        end

        function value = clampToInterval(~, target, interval)
            value = min(max(target, interval(1)), interval(2));
            value = min(max(value, 0), 1);
        end

        function validateNormalizedValue(~, value, label)
            if value < 0 || value > 1
                error("virtualInstrument_nE:InvalidNormalizedValue", ...
                    "%s must be in the range [0, 1]. Received %g.", label, value);
            end
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
