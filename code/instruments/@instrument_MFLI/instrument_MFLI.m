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

            % Configure 4 Sine Generators (Demodulators mapped to Signal Output)
            % In MFLI, "Sine Generators" usually refers to the signal output mixer components.
            % We assume the user means the 4 demodulators' signals summed to SigOut 0.

            for i = 1:4
                demod_idx = i - 1; % 0-based index
                osc_idx = i - 1;   % 0-based index

                % Map Demod i to Osc i
                ziDAQ('setInt', sprintf('/%s/demods/%d/oscselect', obj.device_id, demod_idx), osc_idx);

                % Enable the sine generator on the signal output
                % /devN/sigouts/0/enables/i
                ziDAQ('setInt', sprintf('%senables/%d', sigout_path, demod_idx), 1);

                % Create Channels
                % Amplitude_n
                obj.addChannel(sprintf("Amplitude_%d", i), setTolerances = 1e-3);

                % Phase_n
                obj.addChannel(sprintf("Phase_%d", i), setTolerances = 1e-2);

                % Frequency_n
                obj.addChannel(sprintf("Frequency_%d", i), setTolerances = 1e-3);

                % Harmonic_n
                obj.addChannel(sprintf("Harmonic_%d", i));

                % On_n
                obj.addChannel(sprintf("On_%d", i));
            end

            % Sync to ensure settings are applied
            ziDAQ('sync');
        end

        function delete(obj)
            % Disconnect? ziDAQ doesn't strictly require disconnect, but good practice.
            % ziDAQ('disconnectDevice', obj.address);
        end
    end

    methods (Access = ?instrumentInterface)

        function getWriteChannelHelper(obj, channelIndex)
            % For MFLI settings, getWrite doesn't need to do anything special
            % as we will read the value directly in getRead.
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Optimized channel handling using modular arithmetic
            % Channel order: Amplitude, Phase, Frequency, Harmonic, On (per generator)

            idx_zero = channelIndex - 1;
            group_idx = floor(idx_zero / 5); % 0-3 (Generator Index)
            type_idx = mod(idx_zero, 5);     % 0-4 (Channel Type)

            switch type_idx
                case 0 % Amplitude
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 1 % Phase
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 2 % Frequency
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, group_idx);
                    getValues = ziDAQ('getDouble', path);
                case 3 % Harmonic
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path));
                case 4 % On
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, group_idx);
                    getValues = double(ziDAQ('getInt', path));
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            idx_zero = channelIndex - 1;
            group_idx = floor(idx_zero / 5); % 0-3 (Generator Index)
            type_idx = mod(idx_zero, 5);     % 0-4 (Channel Type)

            switch type_idx
                case 0 % Amplitude
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 1 % Phase
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 2 % Frequency
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, group_idx);
                    ziDAQ('setDouble', path, setValues);
                case 3 % Harmonic
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues));
                case 4 % On
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, group_idx);
                    ziDAQ('setInt', path, int64(setValues));
            end
        end

    end
end
