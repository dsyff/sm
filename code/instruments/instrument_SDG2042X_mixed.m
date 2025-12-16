classdef instrument_SDG2042X_mixed < instrumentInterface
    % SDG2042X mixed multi-tone ARB uploader.
    %
    % Channels (all set-only; read returns cached values):
    % - Amplitude_1..7 (V)
    % - Phase_1..7 (deg)
    % - Frequency_1..7 (Hz)
    % - global_phase_offset (deg)
    %
    % Waveform definition for time vector t (seconds), returned as column:
    % y(t) = sum_i A_i * sin(2*pi*F_i*t + deg2rad(Phase_i + global_offset))
    %
    % Upload happens every time any parameter is changed (setWrite).

    properties (Access = private)
        cachedAmplitude (7, 1) double = zeros(7, 1);
        cachedPhaseDeg (7, 1) double = zeros(7, 1);
        cachedFrequencyHz (7, 1) double = zeros(7, 1);
        cachedGlobalPhaseOffsetDeg (1, 1) double = 0;

        uploadNumPoints (1, 1) double {mustBePositive, mustBeInteger} = 4096;
        uploadFundamentalFrequencyHz (1, 1) double {mustBePositive} = 1;
        waveformNameCH1 (1, 1) string = "MULTI_POS";
        waveformNameCH2 (1, 1) string = "MULTI_NEG";
    end

    methods
        function obj = instrument_SDG2042X_mixed(address)
            obj@instrumentInterface();

            if nargin < 1 || address == ""
                error("SDG2042X address must be specified (e.g. ""USB0::...::INSTR"").");
            end

            handle = visadev(address);
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;

            for sineIndex = 1:7
                obj.addChannel(string(sprintf("Amplitude_%d", sineIndex)), setTolerances = 1e-3);
                obj.addChannel(string(sprintf("Phase_%d", sineIndex)), setTolerances = 1e-3);
                obj.addChannel(string(sprintf("Frequency_%d", sineIndex)), setTolerances = 1e-3);
            end
            obj.addChannel("global_phase_offset", setTolerances = 1e-3);

            obj.resetSettingsOnInit();
        end

        function y = generateMixedSine(obj, t)
            arguments
                obj
                t double {mustBeVector, mustBeNonempty}
            end

            if isrow(t)
                t = t.';
            end

            % cachedAmplitude is interpreted as Vpp (consistent with SDG2042X demos)
            phaseRad = deg2rad(obj.cachedPhaseDeg + obj.cachedGlobalPhaseOffsetDeg);
            omega = 2 * pi * obj.cachedFrequencyHz;
            y = zeros(size(t));
            for sineIndex = 1:7
                y = y + (obj.cachedAmplitude(sineIndex) ./ 2) .* sin(omega(sineIndex) .* t + phaseRad(sineIndex));
            end
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

        function TF = setCheckChannelHelper(~, ~, ~)
            TF = true;
        end
    end

    methods (Access = private)
        function resetSettingsOnInit(obj)
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            pause(1.5);

            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C2:OUTP OFF");
            pause(0.3);

            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C2:OUTP LOAD,HZ");
        end

        function uploadMixedWaveform(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            numPoints = obj.uploadNumPoints;
            fundamentalHz = obj.uploadFundamentalFrequencyHz;

            timeVector = (0:numPoints-1) ./ numPoints; % one period, normalized
            mixedData = zeros(1, numPoints);

            globalOffsetDeg = obj.cachedGlobalPhaseOffsetDeg;
            for sineIndex = 1:7
                ampVpp = obj.cachedAmplitude(sineIndex);
                freqHz = obj.cachedFrequencyHz(sineIndex);
                phaseDeg = obj.cachedPhaseDeg(sineIndex);
                phaseRad = (phaseDeg + globalOffsetDeg) * pi / 180;
                tone = (ampVpp / 2) * sin(2 * pi * (freqHz / fundamentalHz) * timeVector + phaseRad);
                mixedData = mixedData + tone;
            end

            maxAbsValue = max(abs(mixedData));
            if maxAbsValue == 0
                error("Mixed waveform is identically zero; cannot scale/upload. Set at least one nonzero Amplitude_n.");
            end

            actualVpp = max(mixedData) - min(mixedData);
            % SDG2042X expects 16-bit two's-complement waveform samples.
            dacFullScale = double(intmax("int16")); % 32767
            dacScaleFactor = dacFullScale / maxAbsValue;

            dataCH1 = int16(round(mixedData * dacScaleFactor));
            dataCH2 = int16(round(-mixedData * dacScaleFactor));

            obj.uploadWaveformBinary("C1", obj.waveformNameCH1, dataCH1);
            pause(1.5);
            obj.uploadWaveformBinary("C2", obj.waveformNameCH2, dataCH2);
            pause(1.5);

            outputAmplitudeVpp = actualVpp;

            writeline(handle, "C1:OUTP OFF");
            pause(0.3);
            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C1:ARWV NAME," + obj.waveformNameCH1);
            writeline(handle, "C1:BSWV WVTP,ARB");
            writeline(handle, string(sprintf("C1:BSWV FRQ,%d", fundamentalHz)));
            writeline(handle, string(sprintf("C1:BSWV AMP,%.4f", outputAmplitudeVpp * 2)));
            writeline(handle, "C1:BSWV OFST,0");
            writeline(handle, "C1:BSWV PHSE,0");
            writeline(handle, "C1:OUTP ON");

            writeline(handle, "C2:OUTP OFF");
            pause(0.3);
            writeline(handle, "C2:OUTP LOAD,HZ");
            writeline(handle, "C2:ARWV NAME," + obj.waveformNameCH2);
            writeline(handle, "C2:BSWV WVTP,ARB");
            writeline(handle, string(sprintf("C2:BSWV FRQ,%d", fundamentalHz)));
            writeline(handle, string(sprintf("C2:BSWV AMP,%.4f", outputAmplitudeVpp * 2)));
            writeline(handle, "C2:BSWV OFST,0");
            writeline(handle, "C2:BSWV PHSE,0");
            writeline(handle, "C2:OUTP ON");
        end

        function uploadWaveformBinary(obj, channelPrefix, waveformName, dataInt16)
            handle = obj.communicationHandle;

            dataBytes = typecast(dataInt16, 'uint8');
            numBytes = numel(dataBytes);
            lengthStr = string(numBytes);
            binaryHeader = "#" + strlength(lengthStr) + lengthStr;

            commandStr = channelPrefix + ":WVDT WVNM," + waveformName + ",WAVEDATA,";
            terminatorBytes = uint8(10);

            commandBytes = unicode2native(commandStr, "UTF-8");
            headerBytes = unicode2native(binaryHeader, "UTF-8");
            fullMessage = [commandBytes, headerBytes, dataBytes, terminatorBytes];

            maxBytes = 16 * 1024 * 1024;
            if numel(fullMessage) > maxBytes
                error("Final upload command length %d bytes exceeds 16 MB limit (%d bytes). Reduce numPoints and retry.", numel(fullMessage), maxBytes);
            end

            write(handle, fullMessage, 'uint8');
        end
    end
end

