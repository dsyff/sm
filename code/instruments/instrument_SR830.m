classdef instrument_SR830 < instrumentInterface
    % Stanford Research Systems SR830 DSP Lock-in Amplifier
    % Simplified implementation using request/response pattern
    % Migrated from legacy smcSR830.m
    % Thomas 2025-07-17
    
    properties (Access = private)
        sensibilityValues = [2e-9 5e-9 10e-9 20e-9 50e-9 100e-9 200e-9 500e-9 ...
                            1e-6 2e-6 5e-6 10e-6 20e-6 50e-6 100e-6 200e-6 500e-6 ...
                            1e-3 2e-3 5e-3 10e-3 20e-3 50e-3 100e-3 200e-3 500e-3 1e0];
        timeConstValues = [10e-6 30e-6 100e-6 300e-6 1e-3 3e-3 10e-3 30e-3 100e-3 300e-3 ...
                          1e0 3e0 10e0 30e0 100e0 300e0 1e3 3e3 10e3 30e3];
    end

    methods

        function obj = instrument_SR830(address)
            obj@instrumentInterface();
            
            % Create VISA connection
            handle = visadev(address);
            handle.Timeout = 1;
            configureTerminator(handle, "LF");

            % Assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            % Add channels - based on legacy channel mapping
            obj.addChannel("X");                    % Channel 1: X output
            obj.addChannel("Y");                    % Channel 2: Y output  
            obj.addChannel("R");                    % Channel 3: R (magnitude)
            obj.addChannel("Theta");                % Channel 4: Phase
            obj.addChannel("frequency", setTolerances = 1e-6);  % Channel 5: Reference frequency
            obj.addChannel("amplitude", setTolerances = 1e-6);  % Channel 6: Reference amplitude
            obj.addChannel("aux_in_1");             % Channel 7: Aux input 1
            obj.addChannel("aux_in_2");             % Channel 8: Aux input 2
            obj.addChannel("aux_in_3");             % Channel 9: Aux input 3
            obj.addChannel("aux_in_4");             % Channel 10: Aux input 4
            obj.addChannel("aux_out_1", setTolerances = 1e-6);  % Channel 11: Aux output 1
            obj.addChannel("aux_out_2", setTolerances = 1e-6);  % Channel 12: Aux output 2
            obj.addChannel("aux_out_3", setTolerances = 1e-6);  % Channel 13: Aux output 3
            obj.addChannel("aux_out_4", setTolerances = 1e-6);  % Channel 14: Aux output 4
            obj.addChannel("sensitivity", setTolerances = 1e-12); % Channel 15: Sensitivity
            obj.addChannel("time_constant", setTolerances = 1e-9); % Channel 16: Time constant
            obj.addChannel("sync_filter", setTolerances = 0.1);   % Channel 17: Sync filter on/off
            obj.addChannel("XY", 2);                % Channel 18: X,Y simultaneous read
        end

        function delete(obj)
            % Gracefully close connection
            if ~isempty(obj.communicationHandle)
                delete(obj.communicationHandle);
            end
        end

        function reset(obj)
            % Reset instrument to default state
            handle = obj.communicationHandle;
            writeline(handle, "*RST");
            pause(1); % Allow time for reset
        end

    end
    
    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            % Send commands to instrument - separated from reading for optimal batching
            % This allows instrumentRack to minimize reading time by sending all
            % getWrite commands first, then reading all results in sequence
            handle = obj.communicationHandle;
            
            switch channelIndex
                case 1  % X
                    writeline(handle, 'OUTP? 1');
                case 2  % Y
                    writeline(handle, 'OUTP? 2');
                case 3  % R
                    writeline(handle, 'OUTP? 3');
                case 4  % Theta
                    writeline(handle, 'OUTP? 4');
                case 5  % Frequency
                    writeline(handle, 'FREQ?');
                case 6  % Amplitude
                    writeline(handle, 'SLVL?');
                case 7  % Aux in 1
                    writeline(handle, 'OAUX? 1');
                case 8  % Aux in 2
                    writeline(handle, 'OAUX? 2');
                case 9  % Aux in 3
                    writeline(handle, 'OAUX? 3');
                case 10 % Aux in 4
                    writeline(handle, 'OAUX? 4');
                case 11 % Aux out 1
                    writeline(handle, 'AUXV? 1');
                case 12 % Aux out 2
                    writeline(handle, 'AUXV? 2');
                case 13 % Aux out 3
                    writeline(handle, 'AUXV? 3');
                case 14 % Aux out 4
                    writeline(handle, 'AUXV? 4');
                case 15 % Sensitivity
                    writeline(handle, 'SENS?');
                case 16 % Time constant
                    writeline(handle, 'OFLT?');
                case 17 % Sync filter
                    writeline(handle, 'SYNC?');
                case 18 % XY simultaneous
                    writeline(handle, 'SNAP? 1,2');
                otherwise
                    error('Unsupported channel index: %d', channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Read responses from instrument - called after getWriteChannelHelper
            % Instruments need time to physically average data after command is sent
            handle = obj.communicationHandle;
            
            switch channelIndex
                case {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17}  % Single value channels
                    getValues = str2double(strip(readline(handle)));
                case 15 % Sensitivity
                    sensIndex = str2double(strip(readline(handle)));
                    getValues = obj.sensibilityValues(sensIndex + 1);
                case 16 % Time constant
                    tauIndex = str2double(strip(readline(handle)));
                    getValues = obj.timeConstValues(tauIndex + 1);
                case 18 % XY simultaneous
                    response = strip(readline(handle));
                    getValues = str2double(split(response, ','));
                otherwise
                    error('Unsupported channel index: %d', channelIndex);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            handle = obj.communicationHandle;
            
            switch channelIndex
                case 5  % Frequency
                    writeline(handle, sprintf('FREQ %g', setValues));
                case 6  % Amplitude
                    writeline(handle, sprintf('SLVL %g', setValues));
                case 11 % Aux out 1
                    writeline(handle, sprintf('AUXV 1, %g', setValues));
                case 12 % Aux out 2
                    writeline(handle, sprintf('AUXV 2, %g', setValues));
                case 13 % Aux out 3
                    writeline(handle, sprintf('AUXV 3, %g', setValues));
                case 14 % Aux out 4
                    writeline(handle, sprintf('AUXV 4, %g', setValues));
                case 15 % Sensitivity
                    sensIndex = obj.valueToSensitivityIndex(setValues);
                    writeline(handle, sprintf('SENS %d', sensIndex));
                case 16 % Time constant
                    tauIndex = obj.valueToTimeConstantIndex(setValues);
                    writeline(handle, sprintf('OFLT %d', tauIndex));
                case 17 % Sync filter
                    writeline(handle, sprintf('SYNC %d', round(setValues)));
                otherwise
                    error('Set operation not supported for channel %s', ...
                        obj.channelTable.channels(channelIndex));
            end
        end

    end

    methods (Access = private)
        
        function sensIndex = valueToSensitivityIndex(obj, sensValue)
            % Convert sensitivity value to instrument index
            [~, idx] = min(abs(obj.sensibilityValues - sensValue));
            sensIndex = idx - 1;  % SR830 uses 0-based indexing
        end
        
        function tauIndex = valueToTimeConstantIndex(obj, tauValue)
            % Convert time constant value to instrument index
            [~, idx] = min(abs(obj.timeConstValues - tauValue));
            tauIndex = idx - 1;  % SR830 uses 0-based indexing
        end

    end

end
