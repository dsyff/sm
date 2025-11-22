classdef instrument_MFLI < instrumentInterface
    % instrument_MFLI Class for Zurich Instruments MFLI
    % Thomas 20241221

    properties (Access = private)
        device_id;
        props;
    end

    methods
        function obj = instrument_MFLI(address)
            % address is the serial number, e.g., 'dev1234'
            obj@instrumentInterface();
            obj.address = address;

            % Connect to the instrument
            % ziCreateAPISession is in private/ folder
            [obj.device_id, obj.props] = ziCreateAPISession(char(address), 6); % API Level 6 for MFLI

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
                obj.addChannel(sprintf("Amplitude_%d", i));

                % Phase_n
                obj.addChannel(sprintf("Phase_%d", i));

                % Frequency_n
                obj.addChannel(sprintf("Frequency_%d", i));

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
            channelName = obj.channelTable.channels(channelIndex);
            parts = split(channelName, "_");
            type = parts(1);
            idx = str2double(parts(2)); % 1-based index
            zero_idx = idx - 1;

            path = "";
            switch type
                case "Amplitude"
                    % /devN/sigouts/0/amplitudes/i
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, zero_idx);
                case "Phase"
                    % /devN/demods/i/phaseshift
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, zero_idx);
                case "Frequency"
                    % /devN/oscs/i/freq
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, zero_idx);
                case "Harmonic"
                    % /devN/demods/i/harmonic
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, zero_idx);
                case "On"
                    % /devN/sigouts/0/enables/i
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, zero_idx);
            end

            if path ~= ""
                if type == "On" || type == "Harmonic"
                    getValues = double(ziDAQ('getInt', path));
                else
                    getValues = ziDAQ('getDouble', path);
                end
            else
                error("Unknown channel: %s", channelName);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            channelName = obj.channelTable.channels(channelIndex);
            parts = split(channelName, "_");
            type = parts(1);
            idx = str2double(parts(2)); % 1-based index
            zero_idx = idx - 1;

            path = "";
            switch type
                case "Amplitude"
                    path = sprintf('/%s/sigouts/0/amplitudes/%d', obj.device_id, zero_idx);
                    ziDAQ('setDouble', path, setValues);
                case "Phase"
                    path = sprintf('/%s/demods/%d/phaseshift', obj.device_id, zero_idx);
                    ziDAQ('setDouble', path, setValues);
                case "Frequency"
                    path = sprintf('/%s/oscs/%d/freq', obj.device_id, zero_idx);
                    ziDAQ('setDouble', path, setValues);
                case "Harmonic"
                    path = sprintf('/%s/demods/%d/harmonic', obj.device_id, zero_idx);
                    ziDAQ('setInt', path, int64(setValues));
                case "On"
                    path = sprintf('/%s/sigouts/0/enables/%d', obj.device_id, zero_idx);
                    ziDAQ('setInt', path, int64(setValues));
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            % Verify set values are within tolerance
            % For MFLI, we can read back the value.
            channel = obj.channelTable.channels(channelIndex);
            getValues = obj.getReadChannelHelper(channelIndex); % Re-use getRead logic

            % Tolerance check
            if isempty(obj.setTolerances{channelIndex})
                % Default tolerance if not set? Or strict equality for Ints?
                if contains(channel, "On") || contains(channel, "Harmonic")
                    TF = (getValues == channelLastSetValues);
                else
                    TF = abs(getValues - channelLastSetValues) < 1e-9; % Default small tolerance
                end
            else
                TF = all(abs(getValues - channelLastSetValues) <= obj.setTolerances{channelIndex});
            end
        end

    end
end
