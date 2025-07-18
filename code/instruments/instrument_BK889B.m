classdef instrument_BK889B < instrumentInterface
    % Thomas 20241221
    % exclusively for measuring strain cell capacitance displacement sensor

    properties (Access = private)
        unitFactor;
        lastWritten;
        % only triggers a puase between consecutive writelines without
        % readline in-between
        writeInterval = seconds(0.1);
    end

    methods
        
        function obj = instrument_BK889B(address)
            % initialize
            handle = serialport(address, 9600, Timeout = 1);
            configureTerminator(handle, "CR/LF", "LF"); %read terminator, write terminator
            % measurement hardware settings
            writeline(handle, "ASC ON"); % use explicit communication
            pause(seconds(obj.writeInterval));
            writeline(handle, "CPQ"); % measure capacitance in parallel mode for small capacitors.
            pause(seconds(obj.writeInterval));
            % Q=2*pi*f*Cp*Rp
            writeline(handle, "FREQ 200KHz"); % use 200kHz
            pause(seconds(obj.writeInterval));
            writeline(handle, "LEV 1Vrms"); % use 1V AC
            pause(seconds(obj.writeInterval));
            writeline(handle, "RANG pF"); % use pF range
            pause(seconds(obj.writeInterval));
            flush(handle);

            %assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("Cp");
            obj.addChannel("Q");
            obj.addChannel("CpQ", 2);
        end
    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            flush(handle);
            if ~isempty(obj.lastWritten)
                timeToWait = obj.writeInterval - (datetime("now") - obj.lastWritten);
                if timeToWait > 0
                    % this instruments loses commands if written to too
                    % quickly. Normally this is fine because reading waits for
                    % its reply.
                    pause(seconds(timeToWait));
                end
            end
            if  handle.NumBytesAvailable > 0
                flush(handle);
            end

            switch channelIndex
                case {1, 3}
                    writeline(handle, "RANG?");
                    unit = strip(readline(handle));
                    switch unit
                        case "pF"
                            obj.unitFactor = 1E-12;
                        case "nF"
                            obj.unitFactor = 1E-9;
                        case "uF"
                            obj.unitFactor = 1E-6;
                        case "mF"
                            obj.unitFactor = 1E-3;
                        case "F"
                            obj.unitFactor = 1;
                        otherwise
                            error("BK889B driver: unsupported unit: " + unit);
                    end
                case 2
            end
            writeline(handle, "CPQ?");
            obj.lastWritten = datetime("now");
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1
                    outputValues = str2double(split(strip(readline(handle))));
                    getValues = outputValues(1) * obj.unitFactor;
                case 2
                    outputValues = str2double(split(strip(readline(handle))));
                    getValues = outputValues(2);
                case 3
                    getValues = str2double(split(strip(readline(handle))));
                    getValues(1) = getValues(1) * obj.unitFactor;
            end
        end

    end

end