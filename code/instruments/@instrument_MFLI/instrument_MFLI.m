classdef instrument_MFLI < instrumentInterface
    % instrument_MFLI Class for Zurich Instruments MFLI
    % Thomas 20241221

    properties (Access = private)
        device_id;
        props;
    end

    methods
        function obj = instrument_MFLI(address)
            % address is the serial number, e.g., 'dev30037'
            obj@instrumentInterface();

            % Check if address is provided
            if nargin < 1 || isempty(address) || address == ""
                error("MFLI address must be specified (e.g., 'dev30037'). Auto-connect does not work for MFLI.");
            end

            obj.address = address;

            % Connect to the instrument
            % ziCreateAPISession is in private/ folder
            % Enforce MFLI device type
            [obj.device_id, obj.props] = ziCreateAPISession(char(address), 6, 'required_devtype', 'MFLI');

            % Initialize configuration
            % - 1 signal output with differential output
            % - 4 sine generators in that signal output
            % - each sine generator should use a separate oscillator

            % Signal Output 0 (1st output)
            sigout_path = sprintf('/%s/sigouts/0/', obj.device_id);

            % Turn on Signal Output
            ziDAQ('setInt', [sigout_path 'on'], 1);

            % Set Differential Output
            ziDAQ('setInt', [sigout_path 'diff'], 1);

            for i = 1:4
                slot_idx = i - 1;  % 0-based sine generator slot
                osc_idx = i - 1;   % 0-based index

                % Use a separate oscillator for each sine generator.
                ziDAQ('setInt', sprintf('/%s/demods/%d/oscselect', obj.device_id, slot_idx), osc_idx);
                ziDAQ('setInt', sprintf('/%s/demods/%d/enable', obj.device_id, slot_idx), 1);

                % Enable the sine generator on the signal output
                % /devN/sigouts/0/enables/i
                ziDAQ('setInt', sprintf('%senables/%d', sigout_path, slot_idx), 1);

                % Create Channels
                % signal-output sine amplitude_n in V
                obj.addChannel(sprintf("amplitude_%d", i), setTolerances = 1e-3);

                % phase_n in degrees
                obj.addChannel(sprintf("phase_%d", i), setTolerances = 1e-3);

                % signed_amplitude_n in V (phase encodes sign)
                obj.addChannel(sprintf("signed_amplitude_%d", i), setTolerances = 1e-3);

                % oscillator frequency_n in Hz
                obj.addChannel(sprintf("frequency_%d", i));

                % demodulator oscillator_n, user-facing index 1-4
                obj.addChannel(sprintf("oscillator_%d", i));

                % demodulator harmonic_n
                obj.addChannel(sprintf("harmonic_%d", i));

                % output sine enable on signal output 0
                obj.addChannel(sprintf("output_sine_on_%d", i));

                % demodulator enable
                obj.addChannel(sprintf("demod_on_%d", i));

                % demodulator X,Y,R,Theta
                obj.addChannel(sprintf("XYRTheta_%d", i), 4);
            end

            % Sync to ensure settings are applied
            ziDAQ('sync');
        end

        function delete(~)
            % Disconnect? ziDAQ doesn't strictly require disconnect, but good practice.
            % ziDAQ('disconnectDevice', obj.address);
        end
    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(~, ~)
            % For MFLI settings, getWrite doesn't need to do anything special
            % as we will read the value directly in getRead.
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Optimized channel handling using modular arithmetic
            % Channel order: Amplitude, Phase, Signed Amplitude, Frequency, Oscillator, Harmonic, Output Sine On, Demod On, XYRTheta

            idx_zero = channelIndex - 1;
            group_idx = floor(idx_zero / 9); % 0-3 (demodulator/sine slot)
            type_idx = mod(idx_zero, 9);     % 0-8 (Channel Type)

            switch type_idx
                case 0 % Amplitude
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 1 % Phase
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 2 % Signed Amplitude
                    amplitude_path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    phase_path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    amplitude = ziDAQ('getDouble', amplitude_path);
                    phase = ziDAQ('getDouble', phase_path);
                    phase_wrapped = mod(phase, 360);
                    phase_tol = 1; % degrees
                    dist0 = min(phase_wrapped, 360 - phase_wrapped);
                    dist180 = abs(phase_wrapped - 180);
                    if dist0 <= phase_tol
                        getValues = abs(amplitude);
                    elseif dist180 <= phase_tol
                        getValues = -abs(amplitude);
                    else
                        error("signed_amplitude_%d expects phase near 0 or 180 degrees. Received phase %.3f.", group_idx + 1, phase_wrapped);
                    end
                case 3 % Frequency
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 4 % Oscillator
                    path = sprintf('/%s/demods/%d/oscselect', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path)) + 1;
                case 5 % Harmonic
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path));
                case 6 % Output Sine On
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path));
                case 7 % Demod On
                    path = sprintf('/%s/demods/%d/enable', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path));
                case 8 % XYRTheta
                    path = sprintf('/%s/demods/%d/sample', obj.device_id, group_idx);
                    sample = ziDAQ('getSample', path);
                    x = double(sample.x);
                    y = double(sample.y);
                    if ~isscalar(x) || ~isscalar(y)
                        error("MFLI XYRTheta_%d expected scalar x/y sample. Received x length %d, y length %d.", group_idx + 1, numel(x), numel(y));
                    end
                    getValues = [x; y; hypot(x, y); atan2d(y, x)];
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            idx_zero = channelIndex - 1;
            group_idx = floor(idx_zero / 9); % 0-3 (demodulator/sine slot)
            type_idx = mod(idx_zero, 9);     % 0-8 (Channel Type)

            switch type_idx
                case 0 % Amplitude
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 1 % Phase
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 2 % Signed Amplitude
                    amplitude_path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    phase_path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    ziDAQ('setDouble', amplitude_path, abs(setValues));
                    ziDAQ('setDouble', phase_path, 180 * (setValues < 0));
                case 3 % Frequency
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 4 % Oscillator
                    if setValues < 1 || setValues > 4 || setValues ~= round(setValues)
                        error("MFLI oscillator_%d expects an integer oscillator index from 1 to 4. Received %.15g.", group_idx + 1, setValues);
                    end
                    path = sprintf('/%s/demods/%d/oscselect', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues - 1));
                case 5 % Harmonic
                    if setValues < 1 || setValues ~= round(setValues)
                        error("MFLI harmonic_%d expects a positive integer harmonic index. Received %.15g.", group_idx + 1, setValues);
                    end
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues));
                case 6 % Output Sine On
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues));
                case 7 % Demod On
                    path = sprintf('/%s/demods/%d/enable', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues));
                case 8 % XYRTheta
                    error("Set operation not supported for channel %s", obj.channelTable.channels(channelIndex));
            end
        end

    end
end
