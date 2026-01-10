classdef instrument_SDG2042X_pure < instrumentInterface
    % SDG2042X 2-channel pure-tone uploader using DDS (ARB frequency) mode.
    %
    % This implementation is intentionally a 2-channel specialization of
    % instrument_SDG2042X_mixed, preserving the same DDS/ARB semantics and SCPI
    % command ordering/settings.
    %
    % Frequency semantics (matches instrument_SDG2042X_mixed):
    % - A single uploaded waveform period corresponds to 1 / uploadFundamentalFrequencyHz.
    % - Each channel's tone frequency is encoded in the uploaded waveform as
    %   sin(2*pi*frequency_ch*t + phase_ch).
    % - :BSWV FRQ is set to uploadFundamentalFrequencyHz on BOTH channels.
    %
    % Note: With a one-period uploaded waveform, the output is strictly periodic
    % (spectrally pure) when frequency_ch is an integer multiple of
    % uploadFundamentalFrequencyHz.
    %
    % Channels (all set-only; read returns cached values):
    % - amplitude_1..2 (Vpp)
    % - phase_1..2 (deg)
    % - frequency_1..2 (Hz)
    % - global_phase_offset (deg)
    %
    % Upload happens every time any parameter is changed (setWrite).

    properties (Access = private)
        cachedAmplitude (2, 1) double = zeros(2, 1);
        cachedPhaseDeg (2, 1) double = zeros(2, 1);
        cachedFrequencyHz (2, 1) double = zeros(2, 1);
        cachedGlobalPhaseOffsetDeg (1, 1) double = 0;

        waveformNameCH1 (1, 1) string = "DDS_PURE_CH1";
        waveformNameCH2 (1, 1) string = "DDS_PURE_CH2";
    end

    properties (Constant, Access = private)
        arbAmplitudeMultiplier (1, 1) double = 2;
    end

    properties (SetAccess = immutable, GetAccess = private)
        waveformArraySize (1, 1) double
        uploadFundamentalFrequencyHz (1, 1) double
        internalTimebase (1, 1) logical
    end

    methods
        function obj = instrument_SDG2042X_pure(address, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.waveformArraySize (1, 1) double {mustBePositive, mustBeInteger} = 2e5
                NameValueArgs.uploadFundamentalFrequencyHz (1, 1) double {mustBePositive} = 1
                NameValueArgs.internalTimebase (1, 1) logical = true
            end
            obj@instrumentInterface();

            obj.waveformArraySize = double(NameValueArgs.waveformArraySize);
            obj.uploadFundamentalFrequencyHz = NameValueArgs.uploadFundamentalFrequencyHz;
            obj.internalTimebase = NameValueArgs.internalTimebase;

            handle = visadev(address);
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;

            for sineIndex = 1:2
                obj.addChannel(string(sprintf("amplitude_%d", sineIndex)));
                obj.addChannel(string(sprintf("phase_%d", sineIndex)));
                obj.addChannel(string(sprintf("frequency_%d", sineIndex)));
            end
            obj.addChannel("global_phase_offset");

            obj.initializeInstrument();
        end

        function cascadeResyncOnMaster(obj)
            % Force a CASCADE re-handshake by cycling CASCADE state.
            %
            % Siglent application notes indicate that after changing CASCADE settings
            % (e.g., SLAVE delay), a "Sync Devices" action is required on the MASTER
            % to apply new settings. In practice, toggling CASCADE OFF->ON on the
            % master achieves this in a fully-remote workflow.
            %
            % This method only acts when internalTimebase == true (master).
            if ~obj.internalTimebase
                return;
            end
            handle = obj.communicationHandle;
            if isempty(handle)
                return;
            end

            writeline(handle, "CASCADE STATE,OFF,MODE,MASTER");
            pause(0.05);
            writeline(handle, "CASCADE STATE,ON,MODE,MASTER");
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % Cached-only instrument: no I/O.
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex <= 6
                idx0 = channelIndex - 1;
                groupIdx = floor(idx0 / 3) + 1; % 1..2
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
            if channelIndex <= 6
                idx0 = channelIndex - 1;
                groupIdx = floor(idx0 / 3) + 1; % 1..2
                typeIdx = mod(idx0, 3);         % 0..2
                switch typeIdx
                    case 0
                        obj.cachedAmplitude(groupIdx) = setValues;
                    case 1
                        obj.cachedPhaseDeg(groupIdx) = setValues;
                    case 2
                        obj.cachedFrequencyHz(groupIdx) = setValues;
                end

                obj.uploadPureWaveformDDS(groupIdx);
                return;
            end

            % global_phase_offset affects both channels: do two sequential single-channel uploads.
            obj.cachedGlobalPhaseOffsetDeg = setValues;

            obj.uploadPureWaveformDDS(1);
            obj.uploadPureWaveformDDS(2);
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
            % Reset, perform static DDS configuration, then upload initial all-zero waveforms.
            handle = obj.communicationHandle;
            if isempty(handle)
                return;
            end

            writeline(handle, "*RST");
            pause(0.5);

            obj.configureDDSStatic();

            % Use the standard per-channel upload path for the initial upload.
            % With default cached settings, this naturally uploads all-zeros.
            obj.uploadPureWaveformDDS(1);
            obj.uploadPureWaveformDDS(2);

            % Set CASCADE master/slave after the initial waveform upload.
            % Some SDG firmwares behave more reliably when CASCADE mode is set
            % after waveform memory has been initialized by an upload.
            obj.setCascadeModeFromInternalTimebase();

            pause(2);
        end

        function uploadPureWaveformDDS(obj, chIdx)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            channelPrefix = "C" + string(chIdx);
            waveformName = obj.getWaveformNameForChannel(chIdx);

            % Only gate the channel we are updating.
            writeline(handle, channelPrefix + ":OUTP OFF");

            f0 = obj.uploadFundamentalFrequencyHz;
            numPoints = obj.waveformArraySize;

            % Build one-period waveform (period = 1/f0). This matches the
            % normalized construction in SDG2042X_test.m but supports f0 ~= 1.
            fs = numPoints * f0;
            t = (0:numPoints-1) ./ fs; % seconds over one period

            globalOffsetDeg = obj.cachedGlobalPhaseOffsetDeg;

            ampVpp = obj.cachedAmplitude(chIdx);
            freqHz = obj.cachedFrequencyHz(chIdx);
            phaseDeg = obj.cachedPhaseDeg(chIdx);
            phaseRad = (phaseDeg + globalOffsetDeg) * pi / 180;
            waveformData = (ampVpp / 2) * sin(2 * pi * freqHz * t + phaseRad);

            % Remove any residual numerical DC so that OFST can stay at 0 V.
            waveformData = waveformData - mean(waveformData);

            maxAbsValue = max(abs(waveformData));
            % Instrument amplitude (Vpp) defines the full-scale mapping of the DAC.
            % To reproduce the waveform in absolute volts, set AMP to 2*maxAbsValue.
            vppForInstrument = 2 * maxAbsValue;
            if maxAbsValue == 0
                vppForInstrument = 0.002;
            end
            % For reference/debugging only: actual peak-to-peak of the synthesized waveform.
            actualVpp = max(waveformData) - min(waveformData); %#ok<NASGU>

            dacFullScale = double(intmax("int16")); % 32767
            if maxAbsValue == 0
                dacScaleFactor = 0;
            else
                dacScaleFactor = dacFullScale / maxAbsValue;
            end

            dataInt16 = int16(round(waveformData * dacScaleFactor));

            obj.uploadWaveformBinary(channelPrefix, waveformName, dataInt16);

            % Per-update configuration: only amplitude must change.
            obj.setChannelAmplitudeVpp(chIdx, vppForInstrument);

            % Re-select the waveform after upload so the active output refreshes.
            % Without this, the instrument can keep using the previously-cached ARB.
            writeline(handle, channelPrefix + ":ARWV NAME," + waveformName);

            writeline(handle, channelPrefix + ":OUTP ON");
        end

        function configureDDSStatic(obj)
            handle = obj.communicationHandle;
            if obj.internalTimebase
                rosc = "INT";
            else
                rosc = "EXT";
            end

            % Configure both channels identically for DDS/ARB mode.
            writeline(handle, "C1:ROSC:SOUR " + rosc);
            writeline(handle, "C2:ROSC:SOUR " + rosc);

            % Many SDG firmwares accept this to explicitly select DDS mode.
            % If a given unit does not support it, comment it out.
            writeline(handle, "C1:SRATE MODE,DDS");
            writeline(handle, "C2:SRATE MODE,DDS");

            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C2:OUTP LOAD,HZ");

            writeline(handle, "C1:BSWV WVTP,ARB");
            writeline(handle, "C2:BSWV WVTP,ARB");

            f0 = obj.uploadFundamentalFrequencyHz;
            writeline(handle, string(sprintf("C1:BSWV FRQ,%g", f0)));
            writeline(handle, string(sprintf("C2:BSWV FRQ,%g", f0)));

            writeline(handle, "C1:BSWV OFST,0");
            writeline(handle, "C2:BSWV OFST,0");
            writeline(handle, "C1:BSWV PHSE,0");
            writeline(handle, "C2:BSWV PHSE,0");
        end

        function setCascadeModeFromInternalTimebase(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                return;
            end

            if obj.internalTimebase
                mode = "MASTER";
            else
                mode = "SLAVE";
            end

            % Cycle CASCADE state to force the new mode to take effect.
            writeline(handle, "CASCADE STATE,OFF");
            pause(0.05);
            writeline(handle, "CASCADE STATE,ON,MODE," + mode);
            pause(0.05);
        end

        function setChannelAmplitudeVpp(obj, chIdx, vpp)
            handle = obj.communicationHandle;
            scaledVpp = vpp * obj.arbAmplitudeMultiplier;
            writeline(handle, string(sprintf("C%d:BSWV AMP,%.4f", chIdx, scaledVpp)));
        end

        function waveformName = getWaveformNameForChannel(obj, chIdx)
            if chIdx == 1
                waveformName = obj.waveformNameCH1;
            else
                waveformName = obj.waveformNameCH2;
            end
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
                error("Final upload command length %d bytes exceeds 16 MB limit (%d bytes). Reduce waveformArraySize and retry.", numel(fullMessage), maxBytes);
            end

            write(handle, fullMessage, "uint8");
        end
    end
end

