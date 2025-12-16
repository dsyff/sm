classdef instrument_SDG2042X_mixed_TARB < instrumentInterface
    % SDG2042X mixed multi-tone uploader using TrueARB (TARB) sample-rate mode.
    %
    % Channels (all set-only; read returns cached values):
    % - Amplitude_1..7 (Vpp)
    % - Phase_1..7 (deg)
    % - Frequency_1..7 (Hz)
    % - global_phase_offset (deg)
    %
    % Upload happens every time any parameter is changed (setWrite).

    properties (Access = private)
        cachedAmplitude (7, 1) double = zeros(7, 1);
        cachedPhaseDeg (7, 1) double = zeros(7, 1);
        cachedFrequencyHz (7, 1) double = zeros(7, 1);
        cachedGlobalPhaseOffsetDeg (1, 1) double = 0;

        uploadSampleRateHz (1, 1) double {mustBePositive} = 1e6;
        uploadFundamentalFrequencyHz (1, 1) double {mustBePositive} = 1;

        waveformNameCH1 (1, 1) string = "TARB_POS";
        waveformNameCH2 (1, 1) string = "TARB_NEG";
        roscSource (1, 1) string = "INT"; % "INT" or "EXT"
    end

    methods
        function obj = instrument_SDG2042X_mixed_TARB(address)
            obj@instrumentInterface();

            if nargin < 1 || address == ""
                error("SDG2042X address must be specified (e.g. ""USB0::...::INSTR"").");
            end

            handle = visadev(address);
            configureTerminator(handle, "LF");

            obj.address = address;
            obj.communicationHandle = handle;

            for sineIndex = 1:7
                obj.addChannel(string(sprintf("Amplitude_%d", sineIndex)));
                obj.addChannel(string(sprintf("Phase_%d", sineIndex)));
                obj.addChannel(string(sprintf("Frequency_%d", sineIndex)));
            end
            obj.addChannel("global_phase_offset");

            obj.resetSettingsOnInit();
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

            obj.uploadMixedWaveformTARB();
        end

        function TF = setCheckChannelHelper(~, ~, ~)
            TF = true;
        end
    end

    methods (Access = private)
        function resetSettingsOnInit(obj)
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            pause(0.5);

            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C2:OUTP OFF");

            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C2:OUTP LOAD,HZ");
        end

        function uploadMixedWaveformTARB(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            fs = obj.uploadSampleRateHz;
            fundamentalHz = obj.uploadFundamentalFrequencyHz;

            if fs >= 1.2e9
                error("uploadSampleRateHz must be < 1.2e9 Hz for TARB. Received %g Hz.", fs);
            end

            pointsPerPeriod = fs / fundamentalHz;
            numPoints = round(pointsPerPeriod);
            tol = 10 * eps(max(1, abs(pointsPerPeriod)));
            if abs(pointsPerPeriod - numPoints) > tol
                error("TARB requires sampleRate/fundamentalHz to be an integer so the waveform covers exactly one fundamental period. Received sampleRate=%g Hz, fundamentalHz=%g Hz (ratio=%0.15g). Choose fundamentalHz so that sampleRate/fundamentalHz is an integer.", fs, fundamentalHz, pointsPerPeriod);
            end

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

            maxAbsValue = max(abs(mixedData));
            actualVpp = max(mixedData) - min(mixedData);

            dacFullScale = double(intmax("int16")); % 32767
            if maxAbsValue == 0
                dacScaleFactor = 0;
            else
                dacScaleFactor = dacFullScale / maxAbsValue;
            end

            dataCH1 = int16(round(mixedData * dacScaleFactor));
            dataCH2 = int16(round(-mixedData * dacScaleFactor));

            obj.uploadWaveformBinary("C1", obj.waveformNameCH1, dataCH1);
            obj.uploadWaveformBinary("C2", obj.waveformNameCH2, dataCH2);

            % TrueArb configuration (per example_snippet_TARB.txt)
            writeline(handle, "C1:OUTP OFF");
            writeline(handle, "C1:ROSC:SOUR " + obj.roscSource);
            writeline(handle, "C1:SRATE MODE,TARB");
            writeline(handle, string(sprintf("C1:SRATE VALUE,%e", fs)));
            writeline(handle, "C1:OUTP LOAD,HZ");
            writeline(handle, "C1:ARWV NAME," + obj.waveformNameCH1);
            writeline(handle, "C1:BSWV WVTP,ARB");
            writeline(handle, string(sprintf("C1:BSWV AMP,%.4f", actualVpp)));
            writeline(handle, "C1:BSWV OFST,0");
            writeline(handle, "C1:BSWV PHSE,0");
            writeline(handle, "C1:OUTP ON");

            writeline(handle, "C2:OUTP OFF");
            writeline(handle, "C2:ROSC:SOUR " + obj.roscSource);
            writeline(handle, "C2:SRATE MODE,TARB");
            writeline(handle, string(sprintf("C2:SRATE VALUE,%e", fs)));
            writeline(handle, "C2:OUTP LOAD,HZ");
            writeline(handle, "C2:ARWV NAME," + obj.waveformNameCH2);
            writeline(handle, "C2:BSWV WVTP,ARB");
            writeline(handle, string(sprintf("C2:BSWV AMP,%.4f", actualVpp)));
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

