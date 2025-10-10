function strainWatchdogPID(dog2Man, options)
arguments
    dog2Man;
    options.address_E4980AL (1, 1) string;
    options.address_K2450_A (1, 1) string;
    options.address_K2450_B (1, 1) string;
    options.address_Montana2 (1, 1) string;
    options.address_Opticool (1, 1) string;
    options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "Opticool"])};
    options.strainCellNumber (2, 2) uint8 {mustBeInteger, mustBePositive};
    options.pidSettings struct = struct();
end
%% settings
% If last sampling is older than staleTime ago, and if activeControl is on,
% get statements from smc receive error
staleTime = seconds(2);
%dataChunkLength = 2^20; %-
dataChunkLength = 2^16;
temperatureSafeMargin = 3; %K for determining max strain voltage
voltageBoundFraction = 0.9; %- multiplied on computed min/max strain voltage
targetStepVoltage = 0.5; %V step when nudging voltage targets

pidDefaults = struct( ...
    "enabled", false, ...
    "Kp", 0, ...
    "Ki", 0, ...
    "Kd", 0, ...
    "integralLimit", targetStepVoltage, ...
    "outputLimit", targetStepVoltage, ...
    "antiWindup", "clamp", ...
    "derivativeFilter", 0);

pidSettings = resolvePidSettings(options.pidSettings, pidDefaults);

%% pass back man2dog message channel
% man2dog commands will only be executed after initilizations are done.
man2Dog = parallel.pool.DataQueue;
send(dog2Man, man2Dog);

%% initialize variables all in SI units
% whether to keep the dog alive. used to gracefully stop the dog.
keepAlive = true;
% only used when activeControl is on
activeControlVariables.del_d = nan; %m
activeControlVariableSetValues.del_d = nan; %m
% always usable
alwaysControlVariables.T = nan; %K
alwaysControlVariableSetValues.T = nan; %K
% only used when activeControl is on
atTarget.del_d = false;
atTarget.T = false;
% read only
readOnlyVariables.Cp = nan; %F
readOnlyVariables.Q = nan; %-
readOnlyVariables.C = nan; %F
readOnlyVariables.d = nan; %m
readOnlyVariables.I_str_o = nan; %A
readOnlyVariables.I_str_i = nan; %A
% only used when activeControl is off
directControlVariables.V_str_o = nan;%read only if activeControl is on
directControlVariables.V_str_i = nan;
% parameters, can only be set when activeControl is off
parameterVariables.d_0 = nan; %m
parameterVariables.Z_short_r = nan; %Ohm
parameterVariables.Z_short_theta = nan; %rad
parameterVariables.Z_open_r = nan; %Ohm
parameterVariables.Z_open_theta = nan; %rad
parameterVariables.frequency = nan; %Hz
% lastUpdate records last PID step timestamp.
lastUpdate = datetime(0,1,1,0,0,0,0);
% when activeControl is on, dog will turn on PID control
activeControl = false;
% data from finding d_0
tareData = [];
%% initialize variables for activeControl logic
del_d_target = nan; %stores old target so loop knows when new target is set
T_target = nan; %stores old target so loop knows when new target is set
currentData = [];
oldData = [];
unfilledDataRow = [];
V_str_o_max = nan;
V_str_o_min = nan;
V_str_i_max = nan;
V_str_i_min = nan;
justEndedActiveControl = false;
rampToAnchor = true;
pidState = initializePidState();
refreshDataTimetablesAndLoopVariables(false);

%% initilize instruments
%%
rack_strain = instrumentRack(true);
rack_strain.tryTimes = inf;
%%
handle_E4980AL = instrument_E4980AL(options.address_E4980AL);
rack_strain.addInstrument(handle_E4980AL, "E4980AL");
rack_strain.addChannel("E4980AL", "Cp", "Cp");
rack_strain.addChannel("E4980AL", "Q", "Q");
rack_strain.addChannel("E4980AL", "CpQ", "CpQ");

%%
if options.cryostat == "Montana2"
    handle_cryostat = instrument_Montana2(options.address_Montana2);
    rack_strain.addInstrument(handle_cryostat, "Montana2");
    rack_strain.addChannel("Montana2", "T", "T");
elseif options.cryostat == "Opticool"
    handle_cryostat = instrument_Opticool(options.address_Opticool);
    rack_strain.addInstrument(handle_cryostat, "Opticool");
    rack_strain.addChannel("Opticool", "T", "T");
    %rack_strain.addChannel("Opticool", "B", "B");
end

%%
handle_K2450_A = instrument_K2450(options.address_K2450_A);
%handle_K2450_A.reset();
h = handle_K2450_A.communicationHandle;
%writeline(h,"source:voltage:read:back off"); %do not measure voltage

%writeline(h,":sense:current:range 1e-7"); %sets the sense current range
%writeline(h,"source:voltage:Ilimit 8e-8"); %sets a current limit protector

writeline(h,":sense:current:range 1e-6"); %sets the sense current range
writeline(h,"source:voltage:Ilimit 3.2e-7"); %sets a current limit protector

writeline(h,":source:voltage:range 200"); %sets the source voltage range
%writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
%writeline(h,":route:terminals rear"); %use rear terminal
%writeline(h,":sense:current:NPLcycles 2"); %number of power line cycles per measurement
writeline(h,":OUTP ON");
pause(2);
handle_K2450_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
handle_K2450_A.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
rack_strain.addInstrument(handle_K2450_A, "K2450_A");
rack_strain.addChannel("K2450_A", "V_source", "V_str_o");
rack_strain.addChannel("K2450_A", "I_measure", "I_str_o");
rack_strain.addChannel("K2450_A", "VI", "VI_str_o");
%%
handle_K2450_B = instrument_K2450(options.address_K2450_B);
%handle_K2450_B.reset();
h = handle_K2450_B.communicationHandle;
%writeline(h,"source:voltage:read:back off"); %do not measure voltage

%writeline(h,":sense:current:range 1e-7"); %sets the sense current range
%writeline(h,"source:voltage:Ilimit 5e-8"); %sets a current limit protector

writeline(h,":sense:current:range 1e-6"); %sets the sense current range
writeline(h,"source:voltage:Ilimit 2e-7"); %sets a current limit protector

writeline(h,":source:voltage:range 200"); %sets the source voltage range
%writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
%writeline(h,":route:terminals rear"); %use rear terminal
%writeline(h,":sense:current:NPLcycles 2"); %number of power line cycles per measurement
writeline(h,":OUTP ON");
pause(2);
handle_K2450_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
handle_K2450_B.setSetTolerances("V_source", 5E-3); %used to determine if voltage has been reached
rack_strain.addInstrument(handle_K2450_B, "K2450_B");
rack_strain.addChannel("K2450_B", "V_source", "V_str_i");
rack_strain.addChannel("K2450_B", "I_measure", "I_str_i");
rack_strain.addChannel("K2450_B", "VI", "VI_str_i");
%% create cleanup object that tries to ramp down voltages if strainWatchdog was not closed gracefully
cleanupObj = onCleanup(@() rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]));
%%
logFolder = "doglog";
if ~isfolder(logFolder)
    mkdir(logFolder);
end
dataTimetableFolder = "dogTimetable";
if ~isfolder(dataTimetableFolder)
    mkdir(dataTimetableFolder);
end

%% get current target temperature
alwaysControlVariableSetValues.T = handle_cryostat.getCurrentTargetTemperature();

%% set del_d target
activeControlVariableSetValues.del_d = 0;

%% start listening to commands
afterEach(man2Dog, @dogGetsCommand);
%% start infinite loop
% without try/catch, matlab sometimtes fails to handle error here correctly
% and instead restarts the worker with no warning
try
    while keepAlive
        %the dog works on controlling strain here
        if activeControl
            % react to target changes and temperature changes
            if del_d_target ~= activeControlVariableSetValues.del_d
                del_d_target = activeControlVariableSetValues.del_d;
            end
            if T_target ~= alwaysControlVariableSetValues.T
                T_target = alwaysControlVariableSetValues.T;
                rack_strain.rackSetWrite("T", T_target);
            end

            % update current values
            getChannels = ["CpQ", "VI_str_o", "VI_str_i", "T"];
            getValues = rack_strain.rackGet(getChannels);

            readOnlyVariables.Cp = getValues(1);
            readOnlyVariables.Q = getValues(2);
            readOnlyVariables.C = C_comp(getValues(1), getValues(2));
            readOnlyVariables.d = C2d(readOnlyVariables.C);
            readOnlyVariables.I_str_o = getValues(4);
            readOnlyVariables.I_str_i = getValues(6);
            directControlVariables.V_str_o = getValues(3);
            directControlVariables.V_str_i = getValues(5);
            activeControlVariables.del_d = readOnlyVariables.d - parameterVariables.d_0;
            alwaysControlVariables.T = getValues(7);
            newUpdate = datetime("now");
            if newUpdate == lastUpdate
                error("Datetime returned stale time. This is due to a bug in Matlab internal code and cannot be fixed.")
            end
            pidDtSeconds = computePidDeltaSeconds(newUpdate);
            lastUpdate = newUpdate;

            del_V_str_o_max = abs(directControlVariables.V_str_o - V_str_o_max);
            del_V_str_o_min = abs(directControlVariables.V_str_o - V_str_o_min);
            del_V_str_i_0 = abs(directControlVariables.V_str_i - 0);

            % check if voltages reached limit of previous time step
            V_str_o_reached = abs(readOnlyVariables.I_str_o) < 1E-7;
            V_str_i_reached = abs(readOnlyVariables.I_str_i) < 1E-7;
            V_str_o_reached_max = V_str_o_reached && del_V_str_o_max < 5E-3;
            V_str_i_reached_max = V_str_i_reached && abs(directControlVariables.V_str_i - V_str_i_max) < 5E-3;
            %V_str_o_reached_zero = V_str_o_reached && abs(directControlVariables.V_str_o - 0) < 5E-3;
            V_str_i_reached_zero =  V_str_i_reached && del_V_str_i_0 < 5E-3;
            V_str_o_reached_min = V_str_o_reached && del_V_str_o_min < 5E-3;
            V_str_i_reached_min =  V_str_i_reached && abs(directControlVariables.V_str_i - V_str_i_min) < 5E-3;

            reachedMax = V_str_o_reached_max && V_str_i_reached_max;
            reachedMin = V_str_o_reached_min && V_str_i_reached_min;

            atTarget.del_d = ~rampToAnchor && (abs(del_d_target - activeControlVariables.del_d) < 5E-9 || reachedMax || reachedMin);

            % will enforce if T changed elsewhere
            atTarget.T = rack_strain.rackSetCheck("T");
            updateStrainVoltageBounds();

            rampToAnchor = false;
            if del_d_target >= activeControlVariables.del_d
                if V_str_o_reached_max
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_max, pidDtSeconds);
                    V_str_i_target = computeNextVoltage("V_str_i", V_str_i_max, pidDtSeconds);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 1;
                elseif V_str_i_reached_zero
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_max, pidDtSeconds);
                    rack_strain.rackSetWrite("V_str_o", V_str_o_target);
                    branchNum = 2;
                elseif V_str_o_reached_min
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_min, pidDtSeconds);
                    V_str_i_target = computeNextVoltage("V_str_i", 0, pidDtSeconds);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 3;
                else
                    rampToAnchor = true;
                    branchNum = 4;
                end
            else
                if V_str_o_reached_min
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_min, pidDtSeconds);
                    V_str_i_target = computeNextVoltage("V_str_i", V_str_i_min, pidDtSeconds);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 5;
                elseif V_str_i_reached_zero
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_min, pidDtSeconds);
                    rack_strain.rackSetWrite("V_str_o", V_str_o_target);
                    branchNum = 6;
                elseif V_str_o_reached_max
                    V_str_o_target = computeNextVoltage("V_str_o", V_str_o_max, pidDtSeconds);
                    V_str_i_target = computeNextVoltage("V_str_i", 0, pidDtSeconds);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 7;
                else
                    rampToAnchor = true;
                    branchNum = 8;
                end
            end

            if rampToAnchor
                % When neither voltage is near anchor point, prioritize
                % ramping one voltage to anchor point
                % this is to prevent the system from drifitng into V_str_o
                % and V_str_i with opposite signs counteracting each other
                % due to difference in ramp speed of inner and outer
                V_str_o_target = nan;
                V_str_i_target = nan;

                % check out of bounds voltage and ramp back
                if directControlVariables.V_str_o > V_str_o_max
                    V_str_o_target = V_str_o_max;
                elseif directControlVariables.V_str_o < V_str_o_min
                    V_str_o_target = V_str_o_min;
                end
                if directControlVariables.V_str_i > V_str_i_max
                    V_str_i_target = V_str_i_max;
                elseif directControlVariables.V_str_i < V_str_i_min
                    V_str_i_target = V_str_i_min;
                end

                if del_V_str_o_max < del_V_str_i_0 && directControlVariables.V_str_i > 0
                    V_str_o_target = V_str_o_max;
                elseif del_V_str_o_min < del_V_str_i_0 && directControlVariables.V_str_i < 0
                    V_str_o_target = V_str_o_min;
                else
                    V_str_i_target = 0;
                end
                
                if ~isnan(V_str_o_target)
                    rack_strain.rackSetWrite("V_str_o", computeNextVoltage("V_str_o", V_str_o_target, pidDtSeconds));
                end
                if ~isnan(V_str_i_target)
                    rack_strain.rackSetWrite("V_str_i", computeNextVoltage("V_str_i", V_str_i_target, pidDtSeconds));
                end

            end
            % add new entry to data timetable
            %["Cp", "Q", "V_str_o", "I_str_o", "V_str_i", "I_str_i", "T",
            %"C", "del_d", "del_d_target", "branchNum"];
            currentData(unfilledDataRow, :) = num2cell([getValues.', ...
                readOnlyVariables.C, activeControlVariables.del_d, del_d_target, branchNum]); %#ok<AGROW>
            currentData.Time(unfilledDataRow) = lastUpdate;

            if unfilledDataRow == dataChunkLength
                refreshDataTimetablesAndLoopVariables(false);
            else
                unfilledDataRow = unfilledDataRow + 1;
            end
        else
            if justEndedActiveControl
                rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
                refreshDataTimetablesAndLoopVariables(true);
                justEndedActiveControl = false;
                pidState = resetPidState(pidState);
            end
        end

        % This pause is here to ensure this while loop can be interrupted. This
        % causes negligible slowdown.
        pause(1E-5);
    end
    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
    %rack_strain.rackSet(["V_str_o", "V_str_i"], [0, 0]);
catch ME
    saveDataTimetable(currentData);
    send(dog2Man, ME);
    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
    %rack_strain.rackSet(["V_str_o", "V_str_i"], [0, 0]);
end
    function pidDtSeconds = computePidDeltaSeconds(newTimestamp)
        if ~pidSettings.enabled
            pidDtSeconds = 0;
            return;
        end
        if isnat(pidState.general.prevTimestamp)
            pidDtSeconds = 0;
        else
            pidDtSeconds = seconds(newTimestamp - pidState.general.prevTimestamp);
        end
        if pidDtSeconds <= 0
            pidDtSeconds = eps;
        end
        pidState.general.prevTimestamp = newTimestamp;
    end
    function setCurrentDisplacementAsReference(command)
        % error is allowed

        % throw error if some parameter variable has not been set
        assertReadyForTare(command);

        num = command.value;
        values = nan(num, 1);
        for value_index = 1:num
            CPQ = rack_strain.rackGet("CpQ");
            d = C2d(C_comp(CPQ(1), CPQ(2)));
            values(value_index) = d;
        end
        %d_0 = median(values);
        d_0 = median(rmoutliers(values));
        parameterVariables.d_0 = d_0;
        tareData.d_0 = d_0;
        tareData.values = values;
    end

    function getValue = directGet(channel)
        switch channel
            case {"Cp", "Q", "V_str_o", "V_str_i", "I_str_o", "I_str_i", "T"}
                getValue = rack_strain.rackGet(channel);
            case "C"
                CPQ = rack_strain.rackGet("CpQ");
                getValue = C_comp(CPQ(1), CPQ(2));
            case "d"
                CPQ = rack_strain.rackGet("CpQ");
                getValue = C2d(C_comp(CPQ(1), CPQ(2)));
            case "del_d"
                CPQ = rack_strain.rackGet("CpQ");
                d = C2d(C_comp(CPQ(1), CPQ(2)));
                getValue = d - parameterVariables.d_0;
            otherwise
                dogError("Unexpected channel %s in directGet", channel);
        end
    end

    function directSet(channel, setValue)
        switch channel
            case {"V_str_o", "V_str_i", "T"}
                rack_strain.rackSetWrite(channel, setValue);
            otherwise
                dogError("Unexpected channel %s in directSet", channel);
        end
    end

    function nextValue = computeNextVoltage(channel, desiredValue, dtSeconds)
        bounds = getChannelBounds(channel);
        currentValue = directControlVariables.(channel);
        if isnan(currentValue)
            currentValue = 0;
        end
        [nextValue, pidState.(channel)] = pidControllerStep(currentValue, desiredValue, bounds, pidState.(channel), dtSeconds);
    end

    function bounds = getChannelBounds(channel)
        switch channel
            case "V_str_o"
                bounds = [V_str_o_min, V_str_o_max];
            case "V_str_i"
                bounds = [V_str_i_min, V_str_i_max];
            otherwise
                bounds = [-200, 200];
        end
        if any(isnan(bounds))
            bounds = [-200, 200];
        end
        if bounds(1) > bounds(2)
            bounds = sort(bounds);
        end
    end

    function [commandValue, channelState] = pidControllerStep(currentValue, desiredValue, bounds, channelState, dtSeconds)
        if ~pidSettings.enabled
            commandValue = clamp(stepTowards(currentValue, desiredValue), bounds(1), bounds(2));
            channelState = resetPidChannelState(channelState);
            return;
        end

        if dtSeconds <= 0
            dtSeconds = eps;
        end

        errorSignal = desiredValue - currentValue;
        channelState.integral = channelState.integral + pidSettings.Ki * errorSignal * dtSeconds;
        if pidSettings.antiWindup ~= "none"
            channelState.integral = clamp(channelState.integral, -pidSettings.integralLimit, pidSettings.integralLimit);
        end

        if channelState.initialized
            derivative = (errorSignal - channelState.prevError) / dtSeconds;
        else
            derivative = 0;
        end
        if pidSettings.derivativeFilter > 0
            alpha = dtSeconds / (pidSettings.derivativeFilter + dtSeconds);
            derivative = (1 - alpha) * channelState.prevFilteredDerivative + alpha * derivative;
        end
        channelState.prevFilteredDerivative = derivative;

        proportionalTerm = pidSettings.Kp * errorSignal;
        derivativeTerm = pidSettings.Kd * derivative;
        output = proportionalTerm + channelState.integral + derivativeTerm;
        output = clamp(output, -pidSettings.outputLimit, pidSettings.outputLimit);

        delta = clamp(output, -targetStepVoltage, targetStepVoltage);
        commandValue = clamp(currentValue + delta, bounds(1), bounds(2));

        if (commandValue == bounds(1) || commandValue == bounds(2)) && pidSettings.antiWindup == "reset"
            channelState.integral = 0;
        end

        channelState.prevError = errorSignal;
        channelState.initialized = true;
    end

    function matched = activeControlVariableCommands(command)
        % error allowed
        if any(command.channel == string(fieldnames(activeControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    freshSend(activeControlVariables.(command.channel));
                case "SET"
                    if ~isnumeric(command.value)
                        dogError("command.value must be numeric.", command);
                    elseif command.channel == "del_d" && abs(command.value) > 1E-4
                        dogError("target del_d cannot be greater than 100 um in magnitude.", command);
                    else
                        activeControlVariableSetValues.(command.channel) = command.value;
                        atTarget.(command.channel) = false;
                    end
                case "CHECK"
                    send(dog2Man, atTarget.(command.channel));
            end
        else
            matched = false;
        end
    end

    function matched = alwaysControlVariableCommands(command)
        if any(command.channel == string(fieldnames(alwaysControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    freshSend(alwaysControlVariables.(command.channel));
                case "SET"
                    if command.channel ~= "T"
                        dogError("cannot set %s.", command, command.channel);
                    end
                    if ~isnumeric(command.value)
                        dogError("command.value must be numeric.", command);
                    end
                    alwaysControlVariableSetValues.(command.channel) = command.value;
                    atTarget.(command.channel) = false;
                case "CHECK"
                    send(dog2Man, atTarget.(command.channel));
            end
        else
            matched = false;
        end
    end

    function matched = readOnlyVariableCommands(command)
        if any(command.channel == string(fieldnames(readOnlyVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    freshSend(readOnlyVariables.(command.channel));
                case "SET"
                    dogError("cannot set %s.", command, command.channel);
                case "CHECK"
                    dogError("cannot check %s.", command, command.channel);
            end
        else
            matched = false;
        end
    end

    function matched = directControlVariableCommands(command)
        if any(command.channel == string(fieldnames(directControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    freshSend(directControlVariables.(command.channel));
                case "SET"
                    if activeControl
                        dogError("cannot set %s while activeControl is on.", command, command.channel);
                    elseif ~isnumeric(command.value)
                        dogError("command.value must be numeric.", command);
                    else
                        directControlVariables.(command.channel) = command.value;
                        directSet(command.channel, command.value);
                    end
                case "CHECK"
                    dogError("cannot check %s.", command, command.channel);
            end
        else
            matched = false;
        end
    end

    function matched = parameterVariableCommands(command)
        if any(command.channel == string(fieldnames(parameterVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    send(dog2Man, parameterVariables.(command.channel));
                case "SET"
                    if activeControl
                        dogError("cannot set %s while activeControl is on.", command, command.channel);
                    else
                        parameterVariables.(command.channel) = command.value;
                    end
                case "CHECK"
                    dogError("cannot check %s.", command, command.channel);
            end
        else
            matched = false;
        end
    end

    function matched = otherVariableCommands(command)
        if command.channel == "activeControl"
            matched = true;
            switch command.action
                case "GET"
                    send(dog2Man, activeControl);
                case "SET"
                    if ~islogical(command.value) && command.value ~= 0 && command.value ~= 1
                        dogError("command.value for channel ""activeControl"" must be logical, 0, or 1", command);
                    elseif command.value ~= activeControl
                        if command.value
                            assertReadyForActiveControl(command);
                            logParameterVariables();
                            pidState = resetPidState(pidState);
                        else
                            justEndedActiveControl = true;
                            pidState = resetPidState(pidState);
                        end
                        activeControl = logical(command.value);
                    end
                case "CHECK"
                    send(dog2Man, true);
            end
        elseif command.channel == "rack"
            matched = true;
            switch command.action
                case "GET"
                    send(dog2Man, formattedDisplayText(rack_strain));
                case "SET"
                    dogError("cannot set %s.", command, command.channel);
                case "CHECK"
                    dogError("cannot check %s.", command, command.channel);
            end
        elseif command.channel == "tare"
            matched = true;
            switch command.action
                case "GET"
                    if isempty(tareData)
                        dogError("tare has not been done.", command);
                    else
                        send(dog2Man, tareData);
                    end
                case "SET"
                    if activeControl
                        dogError("cannot tare d_0 while activeControl is on.", command);
                    elseif ~isnumeric(command.value)
                        dogError("command.value must be numeric.", command);
                    elseif command.value <= 0
                        dogError("cannot have negative number of times to measure.", command);
                    elseif command.value > 1E3
                        dogError("cannot measure more than 1000 times.", command);
                    else
                        setCurrentDisplacementAsReference(command);
                        logParameterVariables();
                    end
                case "CHECK"
                    dogError("cannot check %s.", command, command.channel);
            end
        else
            matched = false;
        end
    end

    function stringCommands(command)
        if command == "STOP"
            if activeControl
                refreshDataTimetablesAndLoopVariables(true);
            end
            keepAlive = false;
        elseif command == "*IDN?"
            send(dog2Man, "strainWatchdogPID 202412 Prototype");
        elseif command == "ERROR"
            dogError("error requested by man.", command);
        else
            dogError("invalid string command.", command);
        end
    end

    function freshSend(getValue)
        if (datetime("now") - lastUpdate) < staleTime
            send(dog2Man, getValue);
        else
            error("Error: measurement is stale.");
        end
    end

    function dogError(formatSpec, command, varargin)
        error("Error: " + formatSpec + ".\n Command received: \n%s", varargin{:}, formattedDisplayText(command));
    end

    function dogGetsCommand(command)
        try
            if isstruct(command)
                if  ~isfield(command, "channel") || ~isfield(command, "action")
                    dogError("command should be a struct with fields ""channel"" and ""action""", command);
                end
                if all(command.action ~= ["GET", "SET", "CHECK"])
                    dogError("command.action should be ""GET"", ""SET"", or ""CHECK""", command);
                end
                if command.action == "SET"
                    if ~isfield(command, "value")
                        dogError("command should have field ""value"" if command.action is ""set""", command);
                    end
                    if isempty(command.value)
                        dogError("command.value should not be empty if command.action is ""set""", command);
                    end
                end

                switch true
                    case activeControlVariableCommands(command)
                    case alwaysControlVariableCommands(command)
                    case readOnlyVariableCommands(command)
                    case directControlVariableCommands(command)
                    case parameterVariableCommands(command)
                    case otherVariableCommands(command)
                    otherwise
                        dogError("invalid channel name %s.", command, command.channel);
                end
                if command.action == "SET"
                    send(dog2Man, true);
                end
            elseif isstring(command)
                stringCommands(command)
            else
                dogError("command should be a struct or a string", command);
            end
        catch ME
            send(dog2Man, ME);
        end
    end

    function refreshDataTimetablesAndLoopVariables(throwAll)
        recordChannels = ["Cp", "Q", "V_str_o", "I_str_o", "V_str_i", "I_str_i", "T", "C", "del_d", "del_d_target", "branchNum"];
        nanArray = nan(dataChunkLength, length(recordChannels));
        natArray = NaT(dataChunkLength, 1);
        newTimetable = array2timetable(nanArray, RowTimes = natArray, VariableNames = recordChannels);

        if throwAll
            saveDataTimetable(currentData);
            oldData = [];
            currentData = newTimetable;
        elseif isempty(currentData)
            currentData = newTimetable;
        else
            saveDataTimetable(currentData);
            oldData = currentData;
            currentData = newTimetable;
        end
        unfilledDataRow = 1;
    end

    function saveDataTimetable(dataTimetable)
        saveFilename = dataTimetableFolder + filesep + string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
        save(saveFilename + ".mat", "dataTimetable");
        save(saveFilename + ".mat", "-fromstruct", parameterVariables, "-append");
        save(saveFilename + ".mat", "-fromstruct", activeControlVariableSetValues, "-append");
        save(saveFilename + ".mat", "-fromstruct", alwaysControlVariableSetValues, "-append");
        if pidSettings.enabled
            save(saveFilename + ".mat", "-struct", "pidSettings", "-append");
        end
    end

    function assertReadyForActiveControl(command)
        for channel = string(fieldnames(parameterVariables)).'
            if isnan(parameterVariables.(channel))
                dogError("channel %s has not been set.", command, channel);
            end
        end
        if isnan(activeControlVariableSetValues.del_d)
            dogError("channel del_d has not been set.", command);
        end
        if isnan(alwaysControlVariableSetValues.T)
            dogError("channel T has not been set.", command);
        end
    end

    function assertReadyForTare(command)
        for channel = string(fieldnames(parameterVariables)).'
            if channel ~= "d_0" && isnan(parameterVariables.(channel))
                dogError("channel %s has not been set.", command, channel);
            end
        end
    end

    function updateStrainVoltageBounds()
        [V_min, V_max] = strainVoltageBounds(alwaysControlVariables.T + temperatureSafeMargin);

        V_str_o_min = voltageBoundFraction * V_min;
        V_str_o_max = voltageBoundFraction * V_max;

        V_str_i_min = -V_str_o_max;
        V_str_i_max = -V_str_o_min;
    end

    function [minVal, maxVal] = strainVoltageBounds(T)
        if T > 250
            minVal = -20;
            maxVal = 120;
        elseif T > 100
            minVal = -50 + (T - 100) / 5;
            maxVal = 120;
        elseif T > 10
            minVal = -200 + (T - 10) * 5 / 3;
            maxVal = 200 - (T - 10) * 8 / 9;
        else
            minVal = -200;
            maxVal = 200;
        end
    end

    function displacement = C2d(capacitance)
        if options.strainCellNumber == 1
            C_0 = 0.01939E-12;
            alpha = 55.963E-18;
        else
            C_0 = 0.01394E-12;
            alpha = 57.058E-18;
        end
        displacement = alpha ./ (capacitance - C_0);
    end

    function C_compensated = C_comp(C_p, Q)
        omega = parameterVariables.frequency * 2 * pi;
        Z_short = parameterVariables.Z_short_r * (cos(parameterVariables.Z_short_theta) + 1i * sin(parameterVariables.Z_short_theta));
        Z_open = parameterVariables.Z_open_r * (cos(parameterVariables.Z_open_theta) + 1i * sin(parameterVariables.Z_open_theta));

        R_meas = Q ./ (omega * C_p);
        Z_meas = 1 ./ (1i * omega * C_p + 1 ./ R_meas);

        Z_corr = (Z_meas - Z_short) ./ (1 - (Z_meas - Z_short) / Z_open);
        C_compensated = real(1 ./ (1i * omega * Z_corr));
    end

    function settings = resolvePidSettings(customSettings, defaults)
        settings = defaults;
        if isempty(customSettings)
            return;
        end
        if ~isstruct(customSettings)
            error("pidSettings must be a struct.");
        end
        names = fieldnames(customSettings);
        for nameIdx = 1:numel(names)
            name = names{nameIdx};
            if isfield(defaults, name)
                settings.(name) = customSettings.(name);
            end
        end
        settings.enabled = logical(settings.enabled);
        settings.antiWindup = string(settings.antiWindup);
        if settings.antiWindup == ""
            settings.antiWindup = "clamp";
        end
        validAntiWindup = ["clamp", "reset", "none"];
        if ~any(settings.antiWindup == validAntiWindup)
            settings.antiWindup = "clamp";
        end
        settings.derivativeFilter = max(settings.derivativeFilter, 0);
        settings.integralLimit = abs(settings.integralLimit);
        settings.outputLimit = abs(settings.outputLimit);
    end

    function state = initializePidState()
        channelTemplate = struct( ...
            "integral", 0, ...
            "prevError", 0, ...
            "prevFilteredDerivative", 0, ...
            "initialized", false);
        state.V_str_o = channelTemplate;
        state.V_str_i = channelTemplate;
        state.general = struct("prevTimestamp", NaT);
    end

    function state = resetPidState(state)
        state.V_str_o = resetPidChannelState(state.V_str_o);
        state.V_str_i = resetPidChannelState(state.V_str_i);
        state.general.prevTimestamp = NaT;
    end

    function channelState = resetPidChannelState(channelState)
        channelState.integral = 0;
        channelState.prevError = 0;
        channelState.prevFilteredDerivative = 0;
        channelState.initialized = false;
    end

    function nextValue = stepTowards(currentValue, desiredValue)
        delta = desiredValue - currentValue;
        if abs(delta) <= targetStepVoltage
            nextValue = desiredValue;
        else
            nextValue = currentValue + targetStepVoltage * sign(delta);
        end
    end

    function val = clamp(val, low, high)
        val = min(max(val, low), high);
    end

    function logParameterVariables()
        saveFilename = logFolder + filesep + string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
        save(saveFilename + ".mat", "-struct", "parameterVariables");
        if pidSettings.enabled
            save(saveFilename + ".mat", "-struct", "pidSettings", "-append");
        end
    end
end