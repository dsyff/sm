classdef instrument_SDG2042X_pure_DDS < instrumentInterface
    % SDG2042X two-channel pure sine output using DDS (ARB frequency) mode.
    %
    % This is analogous to instrument_SDG2042X_pure (pure sines) but uses the
    % DDS-mode style configuration used by instrument_SDG2042X_mixed_DDS:
    % - Upload ARB waveform data via :WVDT ... WAVEDATA,
    % - Configure output frequency via :BSWV FRQ,<freqHz> (DDS-style)
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

        waveformNameCH1 (1, 1) string = "PUREDDS_1";
        waveformNameCH2 (1, 1) string = "PUREDDS_2";
    end

    properties (SetAccess = immutable, GetAccess = private)
        waveformArraySize (1, 1) double
        internalTimebase (1, 1) logical
        arbAmplitudeMultiplier (1, 1) double
    end

    methods
        function obj = instrument_SDG2042X_pure_DDS(address, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.waveformArraySize (1, 1) double {mustBePositive, mustBeInteger} = 2e5
                NameValueArgs.internalTimebase (1, 1) logical = false
                NameValueArgs.arbAmplitudeMultiplier (1, 1) double {mustBePositive} = 1
            end

            obj@instrumentInterface();

            obj.waveformArraySize = double(NameValueArgs.waveformArraySize);
            obj.internalTimebase = NameValueArgs.internalTimebase;
            obj.arbAmplitudeMultiplier = NameValueArgs.arbAmplitudeMultiplier;

            handle = visadev(address);
            configureTerminator(handle, "LF");
            obj.address = address;
            obj.communicationHandle = handle;

            for ch = 1:2
                obj.addChannel(string(sprintf("amplitude_%d", ch)));
                obj.addChannel(string(sprintf("phase_%d", ch)));
                obj.addChannel(string(sprintf("frequency_%d", ch)));
            end
            obj.addChannel("global_phase_offset");

            obj.resetSettingsOnInit();
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % Cached-only instrument: no pre-query needed.
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex <= 6
                idx0 = channelIndex - 1;
                chIdx = floor(idx0 / 3) + 1; % 1..2
                typeIdx = mod(idx0, 3);      % 0..2
                switch typeIdx
                    case 0
                        getValues = obj.cachedAmplitude(chIdx);
                    case 1
                        getValues = obj.cachedPhaseDeg(chIdx);
                    case 2
                        getValues = obj.cachedFrequencyHz(chIdx);
                end
                return;
            end
            getValues = obj.cachedGlobalPhaseOffsetDeg;
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex <= 6
                idx0 = channelIndex - 1;
                chIdx = floor(idx0 / 3) + 1; % 1..2
                typeIdx = mod(idx0, 3);      % 0..2
                switch typeIdx
                    case 0
                        obj.cachedAmplitude(chIdx) = setValues;
                    case 1
                        obj.cachedPhaseDeg(chIdx) = setValues;
                    case 2
                        obj.cachedFrequencyHz(chIdx) = setValues;
                end
            else
                obj.cachedGlobalPhaseOffsetDeg = setValues;
            end

            obj.uploadPureWaveformsDDS();
        end

        function TF = setCheckChannelHelper(obj, ~, ~)
            % Pass setCheck if either:
            % - the requested waveform is identically zero (all amplitudes are 0), OR
            % - both physical outputs are ON according to instrument query.
            if obj.requestedWaveformIsZero()
                TF = true;
                return;
            end

            TF = obj.areOutputsOn();
        end
    end

    methods (Access = private)
        function TF = requestedWaveformIsZero(obj)
            TF = all(obj.cachedAmplitude == 0);
        end

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

        function resetSettingsOnInit(obj)
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            pause(0.5);

            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C2:OUTP OFF");
            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C2:OUTP LOAD,HZ");
        end

        function uploadPureWaveformsDDS(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            % Keep outputs disabled during the entire update (upload + config),
            % then enable both together at the end.
            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C2:OUTP OFF");

            % Multi-device sync role: internalTimebase => master, external => slave.
            if obj.internalTimebase
                writeline(handle, "CASCADE STATE,ON,MODE,MASTER");
            else
                writeline(handle, "CASCADE STATE,ON,MODE,SLAVE,DELAY,0");
            end

            numPoints = obj.waveformArraySize;
            globalOffsetDeg = obj.cachedGlobalPhaseOffsetDeg;

            % CH1
            [dataCH1, vppCH1] = obj.buildOneCycleSineInt16( ...
                obj.cachedAmplitude(1), obj.cachedPhaseDeg(1) + globalOffsetDeg, numPoints);
            obj.uploadWaveformBinary("C1", obj.waveformNameCH1, dataCH1);

            % CH2
            [dataCH2, vppCH2] = obj.buildOneCycleSineInt16( ...
                obj.cachedAmplitude(2), obj.cachedPhaseDeg(2) + globalOffsetDeg, numPoints);
            obj.uploadWaveformBinary("C2", obj.waveformNameCH2, dataCH2);

            % DDS configuration: set ARB repetition rate (FRQ) per channel.
            obj.configureChannelDDS("C1", obj.waveformNameCH1, obj.cachedFrequencyHz(1), vppCH1);
            obj.configureChannelDDS("C2", obj.waveformNameCH2, obj.cachedFrequencyHz(2), vppCH2);

            writeline(handle, "C1:OUTP ON");
            writeline(handle, "C2:OUTP ON");
        end

        function [dataInt16, vppForInstrument] = buildOneCycleSineInt16(~, ampVpp, phaseDeg, numPoints)
            % Unambiguous convention:
            % - ampVpp is the requested *output* amplitude in Vpp.
            % - We upload a full-scale normalized sine to the ARB (|y| <= 1),
            %   then set the instrument amplitude to ampVpp.
            n = 0:(numPoints - 1);
            theta = 2 * pi * (n ./ numPoints);
            phaseRad = phaseDeg * pi / 180;
            yNorm = sin(theta + phaseRad);

            dacFullScale = double(intmax("int16")); % 32767
            if ampVpp == 0
                dataInt16 = int16(zeros(size(yNorm)));
                vppForInstrument = 0;
                return;
            end

            dataInt16 = int16(round(dacFullScale * yNorm));
            vppForInstrument = ampVpp;
        end

        function configureChannelDDS(obj, channelPrefix, waveformName, outputHz, vpp)
            handle = obj.communicationHandle;
            if obj.internalTimebase
                writeline(handle, channelPrefix + ":ROSC:SOUR INT");
            else
                writeline(handle, channelPrefix + ":ROSC:SOUR EXT");
            end

            % Many SDG firmwares accept this to explicitly select DDS mode.
            % If a given unit does not support it, comment it out.
            writeline(handle, channelPrefix + ":SRATE MODE,DDS");

            writeline(handle, channelPrefix + ":OUTP LOAD,HZ");
            writeline(handle, channelPrefix + ":ARWV NAME," + waveformName);
            writeline(handle, channelPrefix + ":BSWV WVTP,ARB");
            writeline(handle, string(sprintf("%s:BSWV FRQ,%g", channelPrefix, outputHz)));
            writeline(handle, string(sprintf("%s:BSWV AMP,%.4f", channelPrefix, vpp * obj.arbAmplitudeMultiplier)));
            writeline(handle, channelPrefix + ":BSWV OFST,0");
            writeline(handle, channelPrefix + ":BSWV PHSE,0");
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

