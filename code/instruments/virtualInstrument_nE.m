classdef virtualInstrument_nE < virtualInstrumentInterface
    % virtualInstrument_nE - Map normalized n/E inputs to Vtg/Vbg outputs.
    %
    % Provides two write-style channels ("n" and "E") that accept normalized
    % values within [0, 1]. The instrument converts the requested density (n)
    % and displacement field (E) into top-gate and bottom-gate setpoints using
    % the dielectric thickness ratio inferred from two charge-neutrality points.
    %
    % Thomas 20251120
    %
    % The mapping keeps both hardware channels inside their configured limits
    % and stores the latest normalized inputs so that updating either channel
    % automatically re-drives both gates with the appropriate combination.
    %

    properties
        vTgChannelName (1, 1) string {mustBeNonzeroLengthText};
        vBgChannelName (1, 1) string {mustBeNonzeroLengthText};
        vTgLimits (1, 2) double {mustBeFinite};
        vBgLimits (1, 2) double {mustBeFinite};
        cnpTg1 (1, 1) double {mustBeFinite};
        cnpBg1 (1, 1) double {mustBeFinite};
        cnpTg2 (1, 1) double {mustBeFinite};
        cnpBg2 (1, 1) double {mustBeFinite};
        nStored (1, 1) double {mustBeFinite} = 0.5;
        eStored (1, 1) double {mustBeFinite} = 0.5;
    end

    methods

        function obj = virtualInstrument_nE(address, masterRack, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText};
                masterRack (1, 1) instrumentRack;
                NameValueArgs.vTgChannelName (1, 1) string {mustBeNonzeroLengthText};
                NameValueArgs.vBgChannelName (1, 1) string {mustBeNonzeroLengthText};
                NameValueArgs.vTgLimits (1, 2) double {mustBeFinite};
                NameValueArgs.vBgLimits (1, 2) double {mustBeFinite};
                NameValueArgs.cnpTg1 (1, 1) double {mustBeFinite};
                NameValueArgs.cnpBg1 (1, 1) double {mustBeFinite};
                NameValueArgs.cnpTg2 (1, 1) double {mustBeFinite};
                NameValueArgs.cnpBg2 (1, 1) double {mustBeFinite};
            end

            obj@virtualInstrumentInterface(address, masterRack);
            obj.requireSetCheck = true;

            obj.vTgChannelName = NameValueArgs.vTgChannelName;
            obj.vBgChannelName = NameValueArgs.vBgChannelName;
            obj.vTgLimits = obj.sortLimits(NameValueArgs.vTgLimits, "vTgLimits");
            obj.vBgLimits = obj.sortLimits(NameValueArgs.vBgLimits, "vBgLimits");
            obj.cnpTg1 = NameValueArgs.cnpTg1;
            obj.cnpBg1 = NameValueArgs.cnpBg1;
            obj.cnpTg2 = NameValueArgs.cnpTg2;
            obj.cnpBg2 = NameValueArgs.cnpBg2;
            obj.validateCnpPairs();

            obj.addChannel("n");
            obj.addChannel("E");

            obj.initializeStoredState();
        end

    end

    methods (Access = ?instrumentInterface)

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1 % n
                    newValue = setValues(1);
                    obj.validateNormalizedInput(newValue, "n");
                    obj.nStored = newValue;
                    obj.setHardwareFromState();
                case 2 % E
                    newValue = setValues(1);
                    obj.validateNormalizedInput(newValue, "E");
                    obj.eStored = newValue;
                    obj.setHardwareFromState();
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case {1, 2}
                    rack = obj.getMasterRack();
                    TF = rack.rackSetCheck(obj.vTgChannelName) & ...
                        rack.rackSetCheck(obj.vBgChannelName);
                otherwise
                    TF = setCheckChannelHelper@instrumentInterface(obj, channelIndex, channelLastSetValues);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            rack = obj.getMasterRack();
            vtg = rack.rackGet(obj.vTgChannelName);
            vbg = rack.rackGet(obj.vBgChannelName);
            [nNormalized, eNormalized] = obj.computeNormalizedStateFromVoltages(vtg, vbg);

            switch channelIndex
                case 1
                    getValues = nNormalized;
                case 2
                    getValues = eNormalized;
                otherwise
                    error("virtualInstrument_nE:GetUnsupportedChannel", ...
                        "Channel index %d is not supported.", channelIndex);
            end
        end

    end

    methods (Access = private)

        function setHardwareFromState(obj)
            [vtg, vbg] = obj.computeGateVoltages(obj.nStored, obj.eStored);
            rack = obj.getMasterRack();
            rack.rackSetWrite(obj.vTgChannelName, vtg);
            rack.rackSetWrite(obj.vBgChannelName, vbg);

            [nActual, eActual] = obj.computeNormalizedStateFromVoltages(vtg, vbg);
            obj.nStored = nActual;
            obj.eStored = eActual;
        end

        function [vtg, vbg] = computeGateVoltages(obj, nInput, eInput)
            thicknessRatio = obj.computeThicknessRatio();
            cnpCenter = obj.computeCnpCenter();
            ranges = obj.computeLinearRanges(thicknessRatio, cnpCenter);

            nVal = obj.mapNormalizedToRange(nInput, ranges.nMin, ranges.nMax);
            eVal = obj.mapNormalizedToRange(eInput, ranges.eMin, ranges.eMax);

            deltaVtg = 0.5 * thicknessRatio * (nVal + eVal);
            deltaVbg = 0.5 * (nVal - eVal);

            vtg = obj.clamp(cnpCenter(1) + deltaVtg, obj.vTgLimits);
            vbg = obj.clamp(cnpCenter(2) + deltaVbg, obj.vBgLimits);
        end

        function [nNormalized, eNormalized] = computeNormalizedStateFromVoltages(obj, vtg, vbg)
            thicknessRatio = obj.computeThicknessRatio();
            cnpCenter = obj.computeCnpCenter();
            ranges = obj.computeLinearRanges(thicknessRatio, cnpCenter);

            deltaVtg = vtg - cnpCenter(1);
            deltaVbg = vbg - cnpCenter(2);

            nVal = deltaVtg / thicknessRatio + deltaVbg;
            eVal = deltaVtg / thicknessRatio - deltaVbg;

            nNormalized = obj.mapRangeToNormalized(nVal, ranges.nMin, ranges.nMax);
            eNormalized = obj.mapRangeToNormalized(eVal, ranges.eMin, ranges.eMax);
        end

        function val = clamp(~, value, limits)
            val = min(max(value, limits(1)), limits(2));
        end

        function validateNormalizedInput(~, value, label)
            if ~isfinite(value)
                error("virtualInstrument_nE:NonFiniteInput", ...
                    "%s input must be finite.", label);
            end
            if value < 0 || value > 1
                error("virtualInstrument_nE:InputOutOfRange", ...
                    "%s input must be within [0, 1]. Received %g.", label, value);
            end
        end

        function ratio = computeThicknessRatio(obj)
            deltaTg = obj.cnpTg2 - obj.cnpTg1;
            deltaBg = obj.cnpBg2 - obj.cnpBg1;
            if deltaBg == 0
                error("virtualInstrument_nE:CnpDegenerate", ...
                    "CNP entries produce zero ΔVbg; cannot infer dielectric ratio.");
            end
            ratio = abs(deltaTg / deltaBg);
            if ratio == 0
                error("virtualInstrument_nE:CnpDegenerate", ...
                    "CNP entries produce zero ΔVtg; cannot infer dielectric ratio.");
            end
        end

        function center = computeCnpCenter(obj)
            center = [0.5 * (obj.cnpTg1 + obj.cnpTg2), ...
                0.5 * (obj.cnpBg1 + obj.cnpBg2)];
        end

        function ranges = computeLinearRanges(obj, thicknessRatio, cnpCenter)
            tgBounds = sort((2 / thicknessRatio) * (obj.vTgLimits - cnpCenter(1)));
            bgBounds = sort(2 * (obj.vBgLimits - cnpCenter(2)));

            nMin = max(tgBounds(1), bgBounds(1));
            nMax = min(tgBounds(2), bgBounds(2));
            if ~(nMax > nMin)
                error("virtualInstrument_nE:InvalidNRange", ...
                    "Unable to derive a valid n range from provided limits and CNP.");
            end
            if nMin > 0 || nMax < 0
                error("virtualInstrument_nE:CnpOutsideNRange", ...
                    "CNP (n = 0) must lie within the derived n range.");
            end

            tgBoundsE = tgBounds;
            bgBoundsE = sort(2 * (cnpCenter(2) - obj.vBgLimits));
            eMin = max(tgBoundsE(1), bgBoundsE(1));
            eMax = min(tgBoundsE(2), bgBoundsE(2));
            if ~(eMax > eMin)
                error("virtualInstrument_nE:InvalidERange", ...
                    "Unable to derive a valid E range from provided limits and CNP.");
            end
            if eMin > 0 || eMax < 0
                error("virtualInstrument_nE:CnpOutsideERange", ...
                    "CNP (E = 0) must lie within the derived E range.");
            end

            ranges = struct("nMin", nMin, "nMax", nMax, "eMin", eMin, "eMax", eMax);
        end

        function value = mapNormalizedToRange(~, normalized, minVal, maxVal)
            span = maxVal - minVal;
            value = minVal + normalized * span;
        end

        function normalized = mapRangeToNormalized(~, value, minVal, maxVal)
            span = maxVal - minVal;
            normalized = (value - minVal) / span;
            normalized = min(max(normalized, 0), 1);
        end

        function initializeStoredState(obj)
            thicknessRatio = obj.computeThicknessRatio();
            cnpCenter = obj.computeCnpCenter();
            ranges = obj.computeLinearRanges(thicknessRatio, cnpCenter);
            obj.nStored = obj.mapRangeToNormalized(0, ranges.nMin, ranges.nMax);
            obj.eStored = obj.mapRangeToNormalized(0, ranges.eMin, ranges.eMax);
        end

        function validateCnpPairs(obj)
            if obj.cnpTg1 == obj.cnpTg2 && obj.cnpBg1 == obj.cnpBg2
                error("virtualInstrument_nE:DuplicateCnpEntries", ...
                    "CNP entries must describe two distinct operating points.");
            end
        end

        function sorted = sortLimits(~, limits, label)
            sorted = sort(limits);
            if sorted(1) == sorted(2)
                error("virtualInstrument_nE:ZeroSpanLimit", ...
                    "Limits for %s must span a non-zero range.", label);
            end
        end

    end

end


