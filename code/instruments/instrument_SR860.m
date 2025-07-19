classdef instrument_SR860 < instrumentInterface
    % Stanford Research Systems SR860 DSP Lock-in Amplifier
    % Simplified implementation using request/response pattern (like SR830)
    % Migrated from legacy smcSR860.m
    % Thomas 2025-07-17
    % Note: SR860 uses 0-based indexing for AUX channels (different from SR830)
    
    properties (Access = private)
        sensibilityValues = [1e0 5e-1 2e-1 1e-1 5e-2 2e-2 1e-2 5e-3 2e-3 1e-3 ...
                            5e-4 2e-4 1e-4 5e-5 2e-5 1e-5 5e-6 2e-6 1e-6 5e-7 ...
                            2e-7 1e-7 5e-8 2e-8 1e-8 5e-9 2e-9 1e-9]; % in voltage units
        timeConstValues = [1e-6 3e-6 10e-6 30e-6 100e-6 300e-6 1e-3 3e-3 10e-3 30e-3 ...
                          100e-3 300e-3 1e0 3e0 10e0 30e0 100e0 300e0 1e3 3e3 ...
                          10e3 30e3];
    end

    methods

        function obj = instrument_SR860(address)
            obj@instrumentInterface();
            
            % Create VISA connection
            handle = visadev(address);
            handle.Timeout = 0.1;
            configureTerminator(handle, "LF");

            % Assign object properties
            obj.address = address;
            obj.communicationHandle = handle;

            % Add channels - based on legacy channel mapping
            % Note: SR860 uses 0-based indexing for AUX channels
            obj.addChannel("X");                    % Channel 1: X output
            obj.addChannel("Y");                    % Channel 2: Y output  
            obj.addChannel("R");                    % Channel 3: R (magnitude)
            obj.addChannel("Theta");                % Channel 4: Phase
            obj.addChannel("frequency", setTolerances = 1e-6);  % Channel 5: Reference frequency
            obj.addChannel("amplitude", setTolerances = 1e-6);  % Channel 6: Reference amplitude
            obj.addChannel("aux_in_0");             % Channel 7: Aux input 0
            obj.addChannel("aux_in_1");             % Channel 8: Aux input 1
            obj.addChannel("aux_in_2");             % Channel 9: Aux input 2
            obj.addChannel("aux_in_3");             % Channel 10: Aux input 3
            obj.addChannel("aux_out_0", setTolerances = 1e-6);  % Channel 11: Aux output 0
            obj.addChannel("aux_out_1", setTolerances = 1e-6);  % Channel 12: Aux output 1
            obj.addChannel("aux_out_2", setTolerances = 1e-6);  % Channel 13: Aux output 2
            obj.addChannel("aux_out_3", setTolerances = 1e-6);  % Channel 14: Aux output 3
            obj.addChannel("sensitivity", setTolerances = 1e-12); % Channel 15: Sensitivity
            obj.addChannel("time_constant", setTolerances = 1e-9); % Channel 16: Time constant
            obj.addChannel("sync_filter", setTolerances = 0.1);   % Channel 17: Sync filter on/off
            obj.addChannel("XY", 2);                % Channel 18: X,Y simultaneous read
            obj.addChannel("XTheta", 2);            % Channel 19: X,Theta simultaneous read
            obj.addChannel("YTheta", 2);            % Channel 20: Y,Theta simultaneous read
            obj.addChannel("RTheta", 2);            % Channel 21: R,Theta simultaneous read
            obj.addChannel("dc_offset", setTolerances = 1e-6);    % Channel 22: DC output level
        end

        function flush(obj)
            % Flush communication buffer
            flush(obj.communicationHandle);
            pause(0.2); % SR860 flushes extremely slowly
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
            %flush(handle); SR860 flushes extremely slowly
            switch channelIndex
                case 1  % X
                    writeline(handle, 'OUTP? 0');
                case 2  % Y
                    writeline(handle, 'OUTP? 1');
                case 3  % R
                    writeline(handle, 'OUTP? 2');
                case 4  % Theta
                    writeline(handle, 'OUTP? 3');
                case 5  % Frequency
                    writeline(handle, 'FREQ?');
                case 6  % Amplitude
                    writeline(handle, 'SLVL?');
                case 7  % Aux in 0
                    writeline(handle, 'OAUX? 0');
                case 8  % Aux in 1
                    writeline(handle, 'OAUX? 1');
                case 9  % Aux in 2
                    writeline(handle, 'OAUX? 2');
                case 10 % Aux in 3
                    writeline(handle, 'OAUX? 3');
                case 11 % Aux out 0
                    writeline(handle, 'AUXV? 0');
                case 12 % Aux out 1
                    writeline(handle, 'AUXV? 1');
                case 13 % Aux out 2
                    writeline(handle, 'AUXV? 2');
                case 14 % Aux out 3
                    writeline(handle, 'AUXV? 3');
                case 15 % Sensitivity
                    writeline(handle, 'SCAL?');
                case 16 % Time constant
                    writeline(handle, 'OFLT?');
                case 17 % Sync filter
                    writeline(handle, 'SYNC?');
                case 18 % XY simultaneous
                    writeline(handle, 'SNAP? 0,1');
                case 19 % XTheta simultaneous
                    writeline(handle, 'SNAP? 0,3');
                case 20 % YTheta simultaneous
                    writeline(handle, 'SNAP? 1,3');
                case 21 % RTheta simultaneous
                    writeline(handle, 'SNAP? 2,3');
                case 22 % DC offset
                    writeline(handle, 'SOFF?');
                otherwise
                    error('Unsupported channel index: %d', channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Read responses from instrument - called after getWriteChannelHelper
            % Instruments need time to physically average data after command is sent
            handle = obj.communicationHandle;
            
            switch channelIndex
                case {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 22}  % Single value channels
                    getValues = obj.robustReadDouble(handle, channelIndex);
                case 15 % Sensitivity
                    sensIndex = obj.robustReadDouble(handle, channelIndex);
                    getValues = obj.sensibilityValues(sensIndex + 1);
                case 16 % Time constant
                    tauIndex = obj.robustReadDouble(handle, channelIndex);
                    getValues = obj.timeConstValues(tauIndex + 1);
                case {18, 19, 20, 21} % Vector channels: XY, XTheta, YTheta, RTheta
                    getValues = obj.robustReadVector(handle, channelIndex);
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
                case 11 % Aux out 0
                    writeline(handle, sprintf('AUXV 0, %g', setValues));
                case 12 % Aux out 1
                    writeline(handle, sprintf('AUXV 1, %g', setValues));
                case 13 % Aux out 2
                    writeline(handle, sprintf('AUXV 2, %g', setValues));
                case 14 % Aux out 3
                    writeline(handle, sprintf('AUXV 3, %g', setValues));
                case 15 % Sensitivity
                    sensIndex = obj.valueToSensitivityIndex(setValues);
                    writeline(handle, sprintf('SCAL %d', sensIndex));
                case 16 % Time constant
                    tauIndex = obj.valueToTimeConstantIndex(setValues);
                    writeline(handle, sprintf('OFLT %d', tauIndex));
                case 17 % Sync filter
                    writeline(handle, sprintf('SYNC %d', round(setValues)));
                case 22 % DC offset
                    writeline(handle, sprintf('SOFF %g', setValues));
                otherwise
                    error('Set operation not supported for channel %s', ...
                        obj.channelTable.channels(channelIndex));
            end
        end

    end

    methods (Access = private)
        
        function value = robustReadDouble(obj, handle, channelIndex)
            % Robust reading with retry logic for SR860 timeout issues
            % Based on legacy SR860 code - keeps trying until valid response
            % When NaN is returned, re-sends the query command (not just re-reads)
            
            maxAttempts = 10;  % Legacy code used infinite loop, we use reasonable limit
            attempts = 0;
            
            while attempts < maxAttempts
                try
                    response = strip(readline(handle));
                    value = str2double(response);
                    
                    if ~isnan(value)
                        return;  % Success - got valid number
                    end
                    
                    % Handle invalid response (matches legacy behavior exactly)
                    attempts = attempts + 1;
                    disp(datetime);
                    if isempty(response) || response == ""
                        disp("SR860 timed out during query.");
                    else
                        disp("SR860 returned " + response);
                    end
                    
                    % Re-send the query command (this is the key insight from legacy code)
                    obj.getWriteChannelHelper(channelIndex);
                    pause(0.001);

                catch ME
                    attempts = attempts + 1;
                    disp(datetime);
                    disp("SR860 communication error: " + ME.message);
                    
                    % Re-send the query command on communication error too
                    obj.getWriteChannelHelper(channelIndex);
                    pause(0.001);
                end
            end
            
            error('SR860 failed to provide valid response after %d attempts', maxAttempts);
        end
        
        function sensIndex = valueToSensitivityIndex(obj, sensValue)
            % Convert sensitivity value to instrument index
            [~, idx] = min(abs(obj.sensibilityValues - sensValue));
            sensIndex = idx - 1;  % SR860 uses 0-based indexing
        end
        
        function tauIndex = valueToTimeConstantIndex(obj, tauValue)
            % Convert time constant value to instrument index
            [~, idx] = min(abs(obj.timeConstValues - tauValue));
            tauIndex = idx - 1;  % SR860 uses 0-based indexing
        end

        function values = robustReadVector(obj, handle, channelIndex)
            % Robust reading for vector channels with retry logic
            % SNAP command sometimes returns invalid data on SR860
            % Re-sends SNAP command when invalid response received
            maxAttempts = 5;
            attempts = 0;
            
            while attempts < maxAttempts
                try
                    response = strip(readline(handle));
                    values = str2double(split(response, ','));
                    
                    if length(values) == 2 && ~any(isnan(values))
                        return;  % Success - got valid X,Y pair
                    end
                    
                    % Handle invalid response (matches legacy behavior)
                    attempts = attempts + 1;
                    disp(datetime);
                    if isempty(response) || response == ""
                        disp("SR860 SNAP timed out during query (attempt " + attempts + "/" + maxAttempts + ")");
                    else
                        disp("SR860 SNAP returned invalid: " + response + " (attempt " + attempts + "/" + maxAttempts + ")");
                    end
                    
                    if attempts < maxAttempts
                        % Re-send the SNAP command for retry (using getWriteChannelHelper)
                        obj.getWriteChannelHelper(channelIndex);
                        pause(0.001);
                    end
                    
                catch ME
                    attempts = attempts + 1;
                    disp(datetime);
                    disp("SR860 SNAP communication error (attempt " + attempts + "/" + maxAttempts + "): " + ME.message);
                    
                    if attempts < maxAttempts
                        % Re-send the SNAP command for retry
                        obj.getWriteChannelHelper(channelIndex);
                        pause(0.05);
                    end
                end
            end
            
            error('Failed to read valid SNAP response from SR860 after %d attempts', maxAttempts);
        end

    end

end
