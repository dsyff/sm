classdef instrument_K2450_CT < instrumentInterface
    % Continuous-trigger Keithley 2450 driver (source V, measure I).
    properties
        % Used to determine if source voltage has reached target safely.
        chargeCurrentLimit double {mustBePositive} = inf;
        % Continuous trigger-model sample interval in seconds.
        sampleIntervalSeconds (1, 1) double {mustBePositive} = 0.01;
    end

    methods
        function obj = instrument_K2450_CT(address)
            obj@instrumentInterface();
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");
            obj.writeCommandInterval = seconds(0.4);

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("V_source", setTolerances = 5E-4);
            obj.addChannel("I_measure");
            obj.addChannel("VI", 2);

            obj.startContinuousModel();
        end

        function reset(obj)
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            writeline(handle, ":OUTPut ON");
            obj.startContinuousModel();
        end

        function flush(obj)
            % Auto-zero once requires pausing the running trigger model.
            handle = obj.communicationHandle;
            writeline(handle, ":ABORt");
            writeline(handle, ":SENSe:AZERo:ONCE");
            writeline(handle, ":INITiate");
            flush(handle);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            if visastatus(handle)
                flush(handle);
            end
            switch channelIndex
                case 1
                    writeline(handle, ":SOURce:VOLTage?");
                case {2, 3}
                    writeline(handle, ":TRACe:DATA? 1, 1, ""last"", READ");
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    getValues = str2double(strip(readline(handle)));
                case 2
                    getValues = str2double(strip(readline(handle)));
                case 3
                    current = str2double(strip(readline(handle)));
                    writeline(handle, ":SOURce:VOLTage?");
                    sourceValue = str2double(strip(readline(handle)));
                    getValues = [sourceValue; current];
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    writeline(handle, ":SOURce:VOLTage " + string(setValues));
                otherwise
                    setWriteChannelHelper@instrumentInterface(obj, channelIndex, setValues);
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            switch channelIndex
                case 1
                    handle = obj.communicationHandle;
                    writeline(handle, ":SOURce:VOLTage?");
                    sourceValue = str2double(strip(readline(handle)));
                    writeline(handle, ":TRACe:DATA? 1, 1, ""last"", READ");
                    current = str2double(strip(readline(handle)));
                    TF = abs(sourceValue - channelLastSetValues) <= obj.setTolerances{channelIndex};
                    TF = TF && abs(current) < obj.chargeCurrentLimit;
            end
        end
    end

    methods (Access = private)
        function startContinuousModel(obj)
            handle = obj.communicationHandle;
            delayValue = string(obj.sampleIntervalSeconds);
            writeline(handle, ":ABORt");
            writeline(handle, ":TRACe:MAKE ""last"", 1");
            writeline(handle, ":TRACe:CLEar ""last""");
            writeline(handle, ":TRACe:FILL:MODE CONT, ""last""");
            writeline(handle, ":TRIGger:LOAD:EMPTY");
            writeline(handle, ":TRIGger:BLOCk:DELay:CONS 1, " + delayValue);
            writeline(handle, ":TRIGger:BLOCk:MEASure 2, ""last""");
            writeline(handle, ":TRIGger:BLOCk:BRANch:ALWays 3, 1");
            writeline(handle, ":INITiate");
        end
    end
end
