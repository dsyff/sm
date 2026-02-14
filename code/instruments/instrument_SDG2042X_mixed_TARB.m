classdef instrument_SDG2042X_mixed_TARB < instrumentInterface
    % SDG2042X mixed multi-tone uploader using TrueARB sample-rate mode.
    %
    % Channels (all set-only; read returns cached values):
    % - amplitude_1..7 (Vpp)
    % - phase_1..7 (deg)
    % - frequency_1..7 (Hz)
    % - global_phase_offset (deg)
    %
    % Upload happens every time any parameter is changed (setWrite).

    properties (Access = private)
        cachedAmplitude (7, 1) double = zeros(7, 1);
        cachedPhaseDeg (7, 1) double = zeros(7, 1);
        cachedFrequencyHz (7, 1) double = zeros(7, 1);
        cachedGlobalPhaseOffsetDeg (1, 1) double = 0;

        waveformName (1, 1) string = "TARB_MIX";
    end

    properties (SetAccess = immutable, GetAccess = private)
        uploadSampleRateHz (1, 1) double
        uploadFundamentalFrequencyHz (1, 1) double
        waveformArraySize (1, 1) double
        internalTimebase (1, 1) logical
    end

    methods
        function obj = instrument_SDG2042X_mixed_TARB(address, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.waveformArraySize (1, 1) double {mustBePositive, mustBeInteger} = 2e5
                NameValueArgs.uploadFundamentalFrequencyHz (1, 1) double {mustBePositive} = 1
                NameValueArgs.internalTimebase (1, 1) logical = true
            end
            obj@instrumentInterface();
            obj.writeCommandInterval = seconds(5);

            fundamentalHz = NameValueArgs.uploadFundamentalFrequencyHz;
            numPoints = double(NameValueArgs.waveformArraySize);
            fs = numPoints * fundamentalHz;

            if fs >= 1.2e9
                error("Computed sample rate must be < 1.2e9 Hz for TARB. Received %g Hz from waveformArraySize=%g and fundamentalHz=%g.", fs, numPoints, fundamentalHz);
            end

            obj.uploadSampleRateHz = fs;
            obj.uploadFundamentalFrequencyHz = fundamentalHz;
            obj.waveformArraySize = numPoints;
            obj.internalTimebase = NameValueArgs.internalTimebase;

            handle = visadev(address);
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;

            for sineIndex = 1:7
                obj.addChannel(string(sprintf("amplitude_%d", sineIndex)));
                obj.addChannel(string(sprintf("phase_%d", sineIndex)));
                obj.addChannel(string(sprintf("frequency_%d", sineIndex)));
            end
            obj.addChannel("global_phase_offset");

            obj.initializeInstrument();
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % Cached-only instrument: no I/O.
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex <= 21
                idx0 = channelIndex - 1;
                groupIdx = floor(idx0 / 3) + 1; % 1..7
                typeIdx = mod(idx0, 3);         % 0..2
                switch typeIdx
                    case 0
                        getValues = obj.cachedAmplitude(groupIdx);
                    case 1
                        getValues = obj.cachedPhaseDeg(groupIdx);
                    case 2
                        getValues = obj.cachedFrequencyHz(groupIdx);
                end
                return;
            end

            % global_phase_offset
            getValues = obj.cachedGlobalPhaseOffsetDeg;
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex <= 21
                idx0 = channelIndex - 1;
                groupIdx = floor(idx0 / 3) + 1; % 1..7
                typeIdx = mod(idx0, 3);         % 0..2
                switch typeIdx
                    case 0
                        obj.cachedAmplitude(groupIdx) = setValues;
                    case 1
                        obj.cachedPhaseDeg(groupIdx) = setValues;
                    case 2
                        obj.cachedFrequencyHz(groupIdx) = setValues;
                end
            else
                % global_phase_offset
                obj.cachedGlobalPhaseOffsetDeg = setValues;
            end

            obj.uploadMixedWaveform();
        end

        function TF = setCheckChannelHelper(obj, ~, ~)
            % Pass setCheck only when both physical outputs are ON.
            TF = obj.areOutputsOn();
        end
    end

    methods (Access = private)
        function TF = areOutputsOn(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                TF = false;
                return;
            end

            TF = obj.queryChannelOutputOn("C1") && obj.queryChannelOutputOn("C2");
        end

        function TF = queryChannelOutputOn(obj, channelPrefix)
            handle = obj.communicationHandle;
            writeline(handle, channelPrefix + ":OUTP?");
            resp = strtrim(string(readline(handle)));
            respUpper = upper(resp);
            TF = contains(respUpper, "ON") && ~contains(respUpper, "OFF");
        end

        function initializeInstrument(obj)
            % Reset, perform static TARB configuration, then upload initial waveform.
            handle = obj.communicationHandle;
            if isempty(handle)
                return;
            end

            writeline(handle, "*RST");
            pause(0.5);

            obj.configureTARBStatic();
            obj.setMixedChannelPolaritiesStatic();

            % Use the standard upload path for the initial upload.
            obj.uploadMixedWaveform();

            pause(2);
        end

        function uploadMixedWaveform(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            % Keep outputs disabled during the entire update (upload + config),
            % then enable both together at the end.
            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C2:OUTP OFF");

            fs = obj.uploadSampleRateHz;
            numPoints = obj.waveformArraySize;

            t = (0:numPoints-1) ./ fs; % seconds
            mixedData = zeros(1, numPoints);

            globalOffsetDeg = obj.cachedGlobalPhaseOffsetDeg;
            for sineIndex = 1:7
                ampVpp = obj.cachedAmplitude(sineIndex);
                freqHz = obj.cachedFrequencyHz(sineIndex);
                phaseDeg = obj.cachedPhaseDeg(sineIndex);
                phaseRad = (phaseDeg + globalOffsetDeg) * pi / 180;
                tone = (ampVpp / 2) * sin(2 * pi * freqHz * t + phaseRad);
                mixedData = mixedData + tone;
            end

            % Unambiguous convention:
            % - cachedAmplitude values are per-tone output amplitudes in Vpp.
            % - mixedData is constructed in volts.
            % - We upload a normalized waveform (|w| <= 1) and set instrument AMP
            %   to 2*max(abs(mixedData)) so the physical output equals mixedData.
            %
            % Remove any residual numerical DC so that OFST can stay at 0 V.
            mixedData = mixedData - mean(mixedData);

            maxAbsValue = max(abs(mixedData));
            % Instrument amplitude (Vpp) defines the full-scale mapping of the DAC.
            % To reproduce the waveform in absolute volts, set AMP to 2*maxAbsValue.
            vppForInstrument = 2 * maxAbsValue;
            if maxAbsValue == 0
                vppForInstrument = 0.002;
            end
            % For reference/debugging only: actual peak-to-peak of the synthesized waveform.
            actualVpp = max(mixedData) - min(mixedData); %#ok<NASGU>

            dacFullScale = double(intmax("int16")); % 32767
            if maxAbsValue == 0
                dacScaleFactor = 0;
            else
                dacScaleFactor = dacFullScale / maxAbsValue;
            end

            dataCH1 = int16(round(mixedData * dacScaleFactor));

            % Upload a SINGLE waveform, then reference it from both channels.
            obj.uploadWaveformBinary("C1", obj.waveformName, dataCH1);

            % Per-update configuration: only amplitude must change.
            obj.setBothChannelsAmplitudeVpp(vppForInstrument);

            % Re-select the waveform after upload so the active output refreshes.
            % Without this, the instrument can keep using the previously-cached ARB.
            writeline(handle, "C1:ARWV NAME," + obj.waveformName);
            writeline(handle, "C2:ARWV NAME," + obj.waveformName);

            writeline(handle, "C1:OUTP ON");
            writeline(handle, "C2:OUTP ON");
        end

        function configureTARBStatic(obj)
            % Static TrueArb configuration (set once in init).
            handle = obj.communicationHandle;
            if obj.internalTimebase
                rosc = "INT";
            else
                rosc = "EXT";
            end

            writeline(handle, "C1:ROSC:SOUR " + rosc);
            writeline(handle, "C2:ROSC:SOUR " + rosc);

            writeline(handle, "C1:SRATE MODE,TARB");
            writeline(handle, "C2:SRATE MODE,TARB");

            fs = obj.uploadSampleRateHz;
            writeline(handle, string(sprintf("C1:SRATE VALUE,%e", fs)));
            writeline(handle, string(sprintf("C2:SRATE VALUE,%e", fs)));

            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C2:OUTP LOAD,HZ");

            writeline(handle, "C1:BSWV WVTP,ARB");
            writeline(handle, "C2:BSWV WVTP,ARB");
            writeline(handle, "C1:BSWV OFST,0");
            writeline(handle, "C2:BSWV OFST,0");
            writeline(handle, "C1:BSWV PHSE,0");
            writeline(handle, "C2:BSWV PHSE,0");
        end

        function setBothChannelsAmplitudeVpp(obj, vpp)
            handle = obj.communicationHandle;
            writeline(handle, string(sprintf("C1:BSWV AMP,%.4f", vpp)));
            writeline(handle, string(sprintf("C2:BSWV AMP,%.4f", vpp)));
        end

        function setMixedChannelPolaritiesStatic(obj)
            handle = obj.communicationHandle;

            % After reset, both channels default to NOR. Mixed mode requires CH2 inverted.
            writeline(handle, "C2:OUTP PLRT,INVT");
        end

        function uploadWaveformBinary(obj, channelPrefix, waveformName, dataInt16)
            handle = obj.communicationHandle;

            dataBytes = typecast(dataInt16, "uint8");

            commandStr = channelPrefix + ":WVDT WVNM," + waveformName + ",WAVEDATA,";
            terminatorBytes = uint8(10);

            commandBytes = unicode2native(commandStr, "UTF-8");
            fullMessage = [commandBytes, dataBytes, terminatorBytes];

            maxBytes = 16 * 1024 * 1024;
            if numel(fullMessage) > maxBytes
                error("Final upload command length %d bytes exceeds 16 MB limit (%d bytes). Reduce numPoints and retry.", numel(fullMessage), maxBytes);
            end

            write(handle, fullMessage, "uint8");
        end
    end
end

