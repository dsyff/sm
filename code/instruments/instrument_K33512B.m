classdef instrument_K33512B < instrumentInterface
    % Paired K33512B settings; reads report CH1, not measured outputs.
    % frequency: Hz, CH1 = CH2. amplitude: Vrms per channel, CH1 = CH2.
    % dc_offset: V, CH1 = value and CH2 = -value.
    % Startup inverts CH2's AC waveform and sets its DC offset opposite CH1.
    % Configure waveform, load, output enable, phase and CH1 polarity manually.
    % Tracking and amplitude coupling must be OFF. Frequency coupling may
    % be OFF, or ON with ratio 1 / offset 0 Hz. For inverted CH2 AC, use
    % output polarity, not Tracking Invert (which copies the DC offset).
    % Amplitude access selects VRMS units, including on the front panel.
    % Paired writes are sequential. The demo disables set checks; when enabled,
    % they verify CH1 and CH2 separately against their requested targets.

    methods
        function obj = instrument_K33512B(address)
            obj@instrumentInterface();
            handle = visadev(address);
            obj.address = address;
            obj.communicationHandle = handle;
            handle.Timeout = 3;
            configureTerminator(handle, "LF");
            writeline(handle, "OUTP2:POL INV");
            obj.assertNoInstrumentErrors();

            obj.addChannel("frequency", setTolerances = 1e-6);
            obj.addChannel("amplitude", setTolerances = 1e-6);
            obj.addChannel("dc_offset", setTolerances = 1e-6);

            % Preserve CH1's offset and establish the pair before rack use.
            offset = obj.queryNumber("SOUR1:VOLT:OFFS?");
            obj.setWriteChannel("dc_offset", offset);
        end

        function delete(obj)
            delete(obj.communicationHandle);
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            handle = obj.communicationHandle;
            switch channelIndex
                case 1 % frequency
                    writeline(handle, "SOUR1:FREQ?");
                case 2 % amplitude
                    writeline(handle, "SOUR1:VOLT:UNIT VRMS");
                    writeline(handle, "SOUR1:VOLT?");
                case 3 % dc_offset
                    writeline(handle, "SOUR1:VOLT:OFFS?");
            end
        end

        function getValues = getReadChannelHelper(obj, ~)
            getValues = obj.readNumber();
            % In particular, do not report Vpp as Vrms if unit selection failed.
            obj.assertNoInstrumentErrors();
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            % Type, shape and channel index are already checked by the base class.
            if ~isreal(setValues) || ~isfinite(setValues) || ...
                    (channelIndex ~= 3 && setValues <= 0)
                error("instrument_K33512B:InvalidValue", ...
                    "Setpoints must be real and finite; frequency and amplitude must be positive.");
            end
            obj.assertNoInstrumentErrors();
            handle = obj.communicationHandle;

            % These settings are shared by both channels; query each once.
            % Recheck before writes so front-panel changes cannot silently
            % turn opposite DC offsets into equal offsets.
            writeline(handle, "TRAC?");
            tracking = strip(readline(handle));
            if tracking ~= "OFF" || obj.queryNumber("SOUR1:VOLT:COUP:STAT?") ~= 0
                error("instrument_K33512B:CouplingEnabled", ...
                    "Set Tracking and Ampl Cpl OFF manually. No setpoint was written.");
            end
            coupled = obj.queryNumber("SOUR1:FREQ:COUP:STAT?");
            switch coupled
                case 0 % independent frequencies
                case 1 % coupling must preserve equal frequencies
                    writeline(handle, "SOUR1:FREQ:COUP:MODE?");
                    mode = strip(readline(handle));
                    switch mode
                        case "RAT"
                            compatible = obj.queryNumber("SOUR1:FREQ:COUP:RAT?") == 1;
                        case "OFFS"
                            compatible = obj.queryNumber("SOUR1:FREQ:COUP:OFFS?") == 0;
                        otherwise
                            error("instrument_K33512B:InvalidCouplingMode", ...
                                "Unexpected frequency coupling mode: %s.", mode);
                    end
                    if ~compatible
                        error("instrument_K33512B:UnequalFrequencyCoupling", ...
                            "Set frequency coupling OFF, ratio 1, or offset 0 Hz. No setpoint was written.");
                    end
                otherwise
                    error("instrument_K33512B:InvalidCouplingState", ...
                        "Unexpected frequency coupling state: %g.", coupled);
            end

            targets = [setValues, setValues];
            switch channelIndex
                case 1 % frequency
                    command = "FREQ";
                case 2 % amplitude
                    command = "VOLT";
                    writeline(handle, ":SOUR1:VOLT:UNIT VRMS;:SOUR2:VOLT:UNIT VRMS");
                case 3 % dc_offset
                    command = "VOLT:OFFS";
                    targets(2) = -setValues;
            end
            obj.assertNoInstrumentErrors();
            % Reject either channel's range violation before writing either target.
            for ch = 1:2
                low = obj.queryNumber(sprintf("SOUR%d:%s? MIN", ch, command));
                high = obj.queryNumber(sprintf("SOUR%d:%s? MAX", ch, command));
                % Numeric query replies have finite precision at exact limits.
                roundoff = 64*eps([low, high]);
                if targets(ch) < low - roundoff(1) || targets(ch) > high + roundoff(2)
                    error("instrument_K33512B:OutOfRange", ...
                        "CH%d %s target %.15g is outside [%.15g, %.15g]. No setpoint was written.", ...
                        ch, command, targets(ch), low, high);
                end
                targets(ch) = min(max(targets(ch), low), high);
            end
            obj.assertNoInstrumentErrors();
            writeline(handle, sprintf(":SOUR1:%s %.15g;:SOUR2:%s %.15g", ...
                command, targets(1), command, targets(2)));
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            actual = [obj.getChannelByIndex(channelIndex), 0];
            targets = [channelLastSetValues, channelLastSetValues];
            % Four voltage digits: 0.1% bounds one digit of truncation in
            % either Vpp or Vrms. Frequency resolution is fixed at 1 uHz.
            resolution = 1e-3*abs(channelLastSetValues);
            switch channelIndex
                case 1 % frequency
                    command = "FREQ";
                    resolution = 1e-6;
                case 2 % amplitude
                    command = "VOLT";
                    writeline(obj.communicationHandle, "SOUR2:VOLT:UNIT VRMS");
                case 3 % dc_offset
                    command = "VOLT:OFFS";
                    targets(2) = -channelLastSetValues;
            end
            actual(2) = obj.queryNumber(sprintf("SOUR2:%s?", command));
            obj.assertNoInstrumentErrors();
            tolerance = max(obj.setTolerances{channelIndex}, resolution);
            tolerance = tolerance + 8*eps(max(1, abs(channelLastSetValues)));
            TF = all(abs(actual - targets) <= tolerance);
        end
    end

    methods (Access = private)
        function value = readNumber(obj)
            response = strip(readline(obj.communicationHandle));
            value = str2double(response);
            if contains(response, ",") || ~isreal(value) || ~isfinite(value)
                error("instrument_K33512B:InvalidResponse", ...
                    "Expected a finite real numeric reply; received: %s", response);
            end
        end

        function value = queryNumber(obj, command)
            writeline(obj.communicationHandle, command);
            value = obj.readNumber();
        end

        function assertNoInstrumentErrors(obj)
            % Report the first error; do not silently drain the remaining queue.
            writeline(obj.communicationHandle, "SYST:ERR?");
            response = strip(readline(obj.communicationHandle));
            code = str2double(extractBefore(response, ","));
            if ~isreal(code) || ~isfinite(code) || fix(code) ~= code
                error("instrument_K33512B:InvalidErrorResponse", ...
                    "Invalid SYST:ERR? reply: %s", response);
            end
            if code ~= 0
                error("instrument_K33512B:InstrumentError", ...
                    "33512B error: %s. After a write, inspect both outputs for a partially applied pair.", ...
                    response);
            end
        end
    end
end
