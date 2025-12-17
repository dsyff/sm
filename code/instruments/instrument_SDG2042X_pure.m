classdef instrument_SDG2042X_pure < instrumentInterface
    % SDG2042X two-channel pure sine output using TrueARB sample-rate mode.
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

        waveformNameCH1 (1, 1) string = "PURE_1";
        waveformNameCH2 (1, 1) string = "PURE_2";
    end

    properties (SetAccess = immutable, GetAccess = private)
        uploadSampleRateHz (1, 1) double
        uploadFundamentalFrequencyHz (1, 1) double
        waveformArraySize (1, 1) double
        roscSource (1, 1) string
    end

    methods
        function obj = instrument_SDG2042X_pure(address, NameValueArgs)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
                NameValueArgs.waveformArraySize (1, 1) double {mustBePositive, mustBeInteger} = 2e5
                NameValueArgs.uploadFundamentalFrequencyHz (1, 1) double {mustBePositive} = 1
                NameValueArgs.roscSource (1, 1) string {mustBeMember(NameValueArgs.roscSource, ["INT", "EXT"])} = "INT"
            end
            obj@instrumentInterface();

            fundamentalHz = NameValueArgs.uploadFundamentalFrequencyHz;
            numPoints = double(NameValueArgs.waveformArraySize);
            fs = numPoints * fundamentalHz;
            if fs >= 1.2e9
                error("Computed sample rate must be < 1.2e9 Hz for TrueArb. Received %g Hz from waveformArraySize=%g and fundamentalHz=%g.", fs, numPoints, fundamentalHz);
            end

            obj.uploadSampleRateHz = fs;
            obj.uploadFundamentalFrequencyHz = fundamentalHz;
            obj.waveformArraySize = numPoints;
            obj.roscSource = NameValueArgs.roscSource;

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
            % No pre-query needed.
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

            obj.uploadPureWaveforms();
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

        function uploadPureWaveforms(obj)
            handle = obj.communicationHandle;
            if isempty(handle)
                error("SDG2042X communicationHandle is empty; cannot upload waveform.");
            end

            fs = obj.uploadSampleRateHz;
            numPoints = obj.waveformArraySize;
            t = (0:numPoints-1) ./ fs; % seconds

            globalOffsetDeg = obj.cachedGlobalPhaseOffsetDeg;

            % CH1
            [dataCH1, vppCH1] = obj.buildSineWaveformInt16( ...
                obj.cachedAmplitude(1), obj.cachedFrequencyHz(1), obj.cachedPhaseDeg(1) + globalOffsetDeg, t);
            obj.uploadWaveformBinary("C1", obj.waveformNameCH1, dataCH1);

            % CH2
            [dataCH2, vppCH2] = obj.buildSineWaveformInt16( ...
                obj.cachedAmplitude(2), obj.cachedFrequencyHz(2), obj.cachedPhaseDeg(2) + globalOffsetDeg, t);
            obj.uploadWaveformBinary("C2", obj.waveformNameCH2, dataCH2);

            obj.configureChannelTARB("C1", obj.waveformNameCH1, fs, vppCH1);
            obj.configureChannelTARB("C2", obj.waveformNameCH2, fs, vppCH2);
        end

        function [dataInt16, actualVpp] = buildSineWaveformInt16(~, ampVpp, freqHz, phaseDeg, t)
            phaseRad = phaseDeg * pi / 180;
            y = (ampVpp / 2) * sin(2 * pi * freqHz * t + phaseRad);

            actualVpp = max(y) - min(y);
            maxAbsValue = max(abs(y));

            dacFullScale = double(intmax("int16")); % 32767
            if maxAbsValue == 0
                dacScaleFactor = 0;
            else
                dacScaleFactor = dacFullScale / maxAbsValue;
            end
            dataInt16 = int16(round(y * dacScaleFactor));
        end

        function configureChannelTARB(obj, channelPrefix, waveformName, fs, vpp)
            handle = obj.communicationHandle;
            writeline(handle, channelPrefix + ":OUTP OFF");
            writeline(handle, channelPrefix + ":ROSC:SOUR " + obj.roscSource);
            writeline(handle, channelPrefix + ":SRATE MODE,TARB");
            writeline(handle, string(sprintf("%s:SRATE VALUE,%e", channelPrefix, fs)));
            writeline(handle, channelPrefix + ":OUTP LOAD,HZ");
            writeline(handle, channelPrefix + ":ARWV NAME," + waveformName);
            writeline(handle, channelPrefix + ":BSWV WVTP,ARB");
            writeline(handle, string(sprintf("%s:BSWV AMP,%.4f", channelPrefix, vpp)));
            writeline(handle, channelPrefix + ":BSWV OFST,0");
            writeline(handle, channelPrefix + ":BSWV PHSE,0");
            writeline(handle, channelPrefix + ":OUTP ON");
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
                error("Final upload command length %d bytes exceeds 16 MB limit (%d bytes). Reduce waveformArraySize and retry.", numel(fullMessage), maxBytes);
            end

            write(handle, fullMessage, 'uint8');
        end
    end
end

