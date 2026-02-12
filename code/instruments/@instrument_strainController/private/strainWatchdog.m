function strainWatchdog(dog2Man, options)
arguments
    dog2Man;
    options.address_E4980AL (1, 1) string;
    options.address_K2450_A (1, 1) string;
    options.address_K2450_B (1, 1) string;
    options.address_Montana2 (1, 1) string;
    options.address_Opticool (1, 1) string;
    options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "Opticool"])};
    options.strainCellNumber (1, 1) uint8 {mustBeInteger, mustBePositive};
    options.experimentRootPath {mustBeTextScalar} = ""
end
%% settings
% If last sampling is older than staleTime ago, and if activeControl is on,
% get statements from smc receive error
staleTime = seconds(10);
%dataChunkLength = 2^20; %-
dataChunkLength = 2^16;
temperatureSafeMargin = 3; %K for determining max strain voltage
voltageBoundFraction = 0.9; %- multiplied on computed min/max strain voltage
targetStepVoltage = 0.5; %V step when nudging voltage targets. the upper limit to voltage difference
del_d_to_V_gain = 1E6; %V per meter difference for soft ramp. smaller means softer ramp when close (only matters when < 0.5V)
overloadCurrent = 1E-7; %A threshold for considering if ramping or overloading is happening
overloadTolerance = 5E-10; %m tolerance for progress detection. allows a small progress (decrease) in del_d_diff to still be counted as stalling. set to larger than noise level
overloadHold = seconds(5); %time watchdog waits before declaring overload
del_d_tolerance = 5E-9; %m tolerance for determining if del_d target is reached
V_tolerance = 5E-3; %V tolerance for determining if voltage target is reached

%% pass back man2dog message channel
% man2dog commands will only be executed after initilizations are done.
man2Dog = parallel.pool.PollableDataQueue;
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
zeroTime = datetime(0,1,1,0,0,0,0);
lastUpdate = zeroTime;
% when activeControl is on, dog will turn on PID control
activeControl = false;
% data from finding d_0
tareData = [];
%% initialize variables for activeControl logic
del_d_target = nan; %stores old target so loop knows when new target is set
T_target = nan; %stores old target so loop knows when new target is set
currentData = [];
unfilledDataRow = [];
V_str_o_max = nan;
V_str_o_min = nan;
V_str_i_max = nan;
V_str_i_min = nan;
justEndedActiveControl = false;
stallStart = zeroTime;
last_del_d_diff_abs = nan;
rampToAnchor = true;
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
writeline(h,"source:voltage:Ilimit 1.6e-7"); %sets a current limit protector

writeline(h,":source:voltage:range 200"); %sets the source voltage range
%writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
%writeline(h,":route:terminals rear"); %use rear terminal
%writeline(h,":sense:current:NPLcycles 2"); %number of power line cycles per measurement
writeline(h,":OUTP ON");
pause(2);
handle_K2450_A.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
handle_K2450_A.setSetTolerances("V_source", V_tolerance); %used to determine if voltage has been reached
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
writeline(h,"source:voltage:Ilimit 1e-7"); %sets a current limit protector

writeline(h,":source:voltage:range 200"); %sets the source voltage range
%writeline(h,":source:voltage:range:auto ON"); %use auto range for voltage
%writeline(h,":route:terminals rear"); %use rear terminal
%writeline(h,":sense:current:NPLcycles 2"); %number of power line cycles per measurement
writeline(h,":OUTP ON");
pause(2);
handle_K2450_B.chargeCurrentLimit = 1E-7; %used to determine if voltage has been reached on capacitive load
handle_K2450_B.setSetTolerances("V_source", V_tolerance); %used to determine if voltage has been reached
rack_strain.addInstrument(handle_K2450_B, "K2450_B");
rack_strain.addChannel("K2450_B", "V_source", "V_str_i");
rack_strain.addChannel("K2450_B", "I_measure", "I_str_i");
rack_strain.addChannel("K2450_B", "VI", "VI_str_i");
%% create cleanup object that tries to ramp down voltages if strainWatchdog was not closed gracefully
cleanupObj = onCleanup(@() rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]));
%%
rootPath = string(options.experimentRootPath);
if strlength(rootPath) == 0
    rootPath = experimentContext.getExperimentRootPath();
end
if strlength(rootPath) == 0
    rootPath = string(pwd);
end

baseLogDir = fullfile(rootPath, "logs", "strainController");
if ~isfolder(baseLogDir)
    mkdir(baseLogDir);
end

logFolder = fullfile(baseLogDir, "doglog");
if ~isfolder(logFolder)
    mkdir(logFolder);
end

dataTimetableFolder = fullfile(baseLogDir, "dogTimetable");
if ~isfolder(dataTimetableFolder)
    mkdir(dataTimetableFolder);
end

%% get current target temperature
alwaysControlVariableSetValues.T = handle_cryostat.getCurrentTargetTemperature();

%% set del_d target
activeControlVariableSetValues.del_d = 0;

%% start infinite loop
% without try/catch, matlab sometimtes fails to handle error here correctly
% and instead restarts the worker with no warning
try
    while keepAlive
        % Process pending manager commands (PollableDataQueue).
        while man2Dog.QueueLength > 0
            command = poll(man2Dog);
            dogGetsCommand(command);
        end

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
            lastUpdate = newUpdate;

            del_d_diff_abs = abs(del_d_target - activeControlVariables.del_d);
            currMax = max(abs(readOnlyVariables.I_str_o), abs(readOnlyVariables.I_str_i));
            overloaded = false;
            if ~rampToAnchor && del_d_diff_abs >= del_d_tolerance && currMax >= overloadCurrent
                if ~isnan(last_del_d_diff_abs) && del_d_diff_abs >= last_del_d_diff_abs - overloadTolerance
                    if stallStart == zeroTime
                        stallStart = lastUpdate;
                    elseif lastUpdate - stallStart > overloadHold
                        overloaded = true;
                    end
                else
                    stallStart = zeroTime;
                end
            else
                stallStart = zeroTime;
            end
            last_del_d_diff_abs = del_d_diff_abs;

            del_V_str_o_max = abs(directControlVariables.V_str_o - V_str_o_max);
            del_V_str_o_min = abs(directControlVariables.V_str_o - V_str_o_min);
            del_V_str_i_0 = abs(directControlVariables.V_str_i - 0);

            % check if voltages reached limit of previous time step
            V_str_o_reached = abs(readOnlyVariables.I_str_o) < overloadCurrent;
            V_str_i_reached = abs(readOnlyVariables.I_str_i) < overloadCurrent;
            V_str_o_reached_max = V_str_o_reached && del_V_str_o_max < V_tolerance;
            V_str_i_reached_max = V_str_i_reached && abs(directControlVariables.V_str_i - V_str_i_max) < V_tolerance;
            %V_str_o_reached_zero = V_str_o_reached && abs(directControlVariables.V_str_o - 0) < V_tolerance;
            V_str_i_reached_zero =  V_str_i_reached && del_V_str_i_0 < V_tolerance;
            V_str_o_reached_min = V_str_o_reached && del_V_str_o_min < V_tolerance;
            V_str_i_reached_min =  V_str_i_reached && abs(directControlVariables.V_str_i - V_str_i_min) < V_tolerance;

            reachedMax = V_str_o_reached_max && V_str_i_reached_max;
            reachedMin = V_str_o_reached_min && V_str_i_reached_min;

            atTarget.del_d = ~rampToAnchor && (del_d_diff_abs < del_d_tolerance || reachedMax || reachedMin || overloaded);

            % will enforce if T changed elsewhere
            atTarget.T = rack_strain.rackSetCheck("T");
            updateStrainVoltageBounds();

            rampToAnchor = false;
            adaptiveStep = del_d_diff_abs * del_d_to_V_gain;
            if del_d_target >= activeControlVariables.del_d
                if V_str_o_reached_max
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_max, adaptiveStep);
                    V_str_i_target = stepTowards(directControlVariables.V_str_i, V_str_i_max, adaptiveStep);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 1;
                elseif V_str_i_reached_zero
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_max, adaptiveStep);
                    rack_strain.rackSetWrite("V_str_o", V_str_o_target);
                    branchNum = 2;
                elseif V_str_o_reached_min
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_min, adaptiveStep);
                    V_str_i_target = stepTowards(directControlVariables.V_str_i, 0, adaptiveStep);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 3;
                else
                    rampToAnchor = true;
                    branchNum = 4;
                end
            else
                if V_str_o_reached_min
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_min, adaptiveStep);
                    V_str_i_target = stepTowards(directControlVariables.V_str_i, V_str_i_min, adaptiveStep);
                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_target, V_str_i_target]);
                    branchNum = 5;
                elseif V_str_i_reached_zero
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_min, adaptiveStep);
                    rack_strain.rackSetWrite("V_str_o", V_str_o_target);
                    branchNum = 6;
                elseif V_str_o_reached_max
                    V_str_o_target = stepTowards(directControlVariables.V_str_o, V_str_o_max, adaptiveStep);
                    V_str_i_target = stepTowards(directControlVariables.V_str_i, 0, adaptiveStep);
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
                    rack_strain.rackSetWrite("V_str_o", stepTowards(directControlVariables.V_str_o, V_str_o_target));
                end
                if ~isnan(V_str_i_target)
                    rack_strain.rackSetWrite("V_str_i", stepTowards(directControlVariables.V_str_i, V_str_i_target));
                end

            end
            % add new entry to data timetable
            %["Cp", "Q", "V_str_o", "I_str_o", "V_str_i", "I_str_i", "T",
            %"C", "del_d", "del_d_target", "branchNum"];
            currentData(unfilledDataRow, :) = num2cell([getValues.', ...
                readOnlyVariables.C, activeControlVariables.del_d, del_d_target, branchNum]);
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
            end
            stallStart = zeroTime;
            last_del_d_diff_abs = nan;
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

    function nextValue = stepTowards(currentValue, desiredValue, step)
        if nargin < 3 || step <= 0
            step = targetStepVoltage;
        else
            step = min(targetStepVoltage, step);
        end
        delta = desiredValue - currentValue;
        if abs(delta) <= step
            nextValue = desiredValue;
        else
            nextValue = currentValue + step * sign(delta);
        end
    end

    function logParameterVariables()
        saveFilename = logFolder + filesep + string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
        save(saveFilename + ".mat", "-struct", "parameterVariables");
    end

    function matched = activeControlVariableCommands(command)
        % error allowed
        if any(command.channel == string(fieldnames(activeControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    if activeControl
                        freshSend(activeControlVariables.(command.channel));
                    else
                        send(dog2Man, directGet(command.channel));
                    end
                case "SET"
                    activeControlVariableSetValues.(command.channel) = command.value;
                case "CHECK"
                    if activeControl
                        freshSend(atTarget.(command.channel));
                    else
                        dogError("cannot check %s while activeControl is off.", command, command.channel);
                    end
            end
        else
            matched = false;
        end
    end

    function matched = alwaysControlVariableCommands(command)
        % error allowed
        if any(command.channel == string(fieldnames(alwaysControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    if activeControl
                        freshSend(alwaysControlVariables.(command.channel));
                    else
                        send(dog2Man, directGet(command.channel));
                    end
                case "SET"
                    alwaysControlVariableSetValues.(command.channel) = command.value;
                    if ~activeControl
                        directSet(command.channel, command.value);
                    end
                case "CHECK"
                    if activeControl
                        freshSend(atTarget.(command.channel));
                    else
                        send(dog2Man, rack_strain.rackSetCheck(command.channel));
                    end
            end
        else
            matched = false;
        end
    end


    function matched = readOnlyVariableCommands(command)
        % error allowed
        if any(command.channel == string(fieldnames(readOnlyVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    if activeControl
                        freshSend(readOnlyVariables.(command.channel));
                    else
                        send(dog2Man, directGet(command.channel));
                    end
                case "SET"
                    dogError("cannot set channel %s.", command, command.channel);
                case "CHECK"
                    dogError("cannot check channel %s.", command, command.channel);
            end
        else
            matched = false;
        end
    end


    function matched = directControlVariableCommands(command)
        % error allowed
        if any(command.channel == string(fieldnames(directControlVariables)).')
            matched = true;
            switch command.action
                case "GET"
                    if activeControl
                        freshSend(directControlVariables.(command.channel));
                    else
                        send(dog2Man, directGet(command.channel));
                    end
                case "SET"
                    if activeControl
                        dogError("cannot set %s while activeControl is on.", command, command.channel);
                    else
                        directSet(command.channel, command.value);
                    end
                case "CHECK"
                    if activeControl
                        dogError("cannot check %s while activeControl is on.", command, command.channel);
                    else
                        send(dog2Man, rack_strain.rackSetCheck(command.channel));
                    end
            end
        else
            matched = false;
        end
    end

    function matched = parameterVariableCommands(command)
        % error allowed
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
        % error allowed
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
                            % will throw error for unset variables
                            assertReadyForActiveControl(command);
                            logParameterVariables();
                        else
                            justEndedActiveControl = true;
                        end
                        activeControl = command.value;
                    end
                case "CHECK"
                    send(dog2Man, true);
            end
        elseif command.channel == "rack"
            matched = true;
            switch command.action
                case "GET"
                    send(dog2Man, string(formattedDisplayText(rack_strain)));
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
                        % will throw error if any parameter is nan
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
        % error allowed
        if command == "STOP"
            % end watchdog.
            if activeControl
                refreshDataTimetablesAndLoopVariables(true);
            end
            keepAlive = false;
        elseif command == "*IDN?"
            send(dog2Man, "strainWatchdog 202412 Thomas");
        elseif command == "ERROR"
            dogError("error requested by man.", command);
        else
            dogError("invalid string command.", command);
        end
    end

    function freshSend(getValue)
        % error allowed
        if (datetime("now") - lastUpdate) < staleTime
            send(dog2Man, getValue);
        else
            error("Error: measurement is stale.");
        end
    end

    function dogError(formatSpec, command, varargin)
        % error allowed
        % send(dog2Man, sprintf("Error: " + formatSpec + ".\n Command received: \n%s", varargin{:}, formattedDisplayText(command)));
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

                % commands that may be used in a scan come before other
                % commands
                % due to dogGetsCommand being used in afterEach as an
                % interrupt, its errors do not get thrown upward. the try catch
                % here handles any error incurred and sends them to man via
                % dog2Man
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
            % turning off activeControl
            saveDataTimetable(currentData);
            currentData = newTimetable;
        elseif isempty(currentData)
            % when turning on activeControl for the first time
            currentData = newTimetable;
        else
            % currentData is full
            saveDataTimetable(currentData);
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

        % outer voltages are connected so that positive corresponds to
        % stretch

        V_str_o_min = voltageBoundFraction * V_min;
        V_str_o_max = voltageBoundFraction * V_max;

        % inner voltages are connected so that negative corresponds to
        % stretch
        V_str_i_min = -V_str_o_max;
        V_str_i_max = -V_str_o_min;
    end

    function [min, max] = strainVoltageBounds(T)
        if T > 250
            min = -20;
            max = 120;
        elseif T > 100
            min = -50 + (T - 100) / 5;
            max = 120;
        elseif T > 10
            min = -200 + (T - 10) * 5 / 3;
            max = 200 - (T - 10) * 8 / 9;
        else
            min = -200;
            max = 200;
        end
    end

    function displacement = C2d(capacitance)
        % conversion from capacitance to displacement
        if options.strainCellNumber == 1
            C_0 = 0.01939E-12;
            alpha = 55.963E-18;
        elseif options.strainCellNumber == 2
            C_0 = 0.01394E-12;
            alpha = 57.058E-18;
        end
        displacement = alpha ./ (capacitance - C_0);
    end

    function C_compensated = C_comp(C_p, Q)
        % open and short compensation
        omega = parameterVariables.frequency * 2 * pi;
        Z_short = parameterVariables.Z_short_r * (cos(parameterVariables.Z_short_theta) + 1i * sin(parameterVariables.Z_short_theta));
        Z_open = parameterVariables.Z_open_r * (cos(parameterVariables.Z_open_theta) + 1i * sin(parameterVariables.Z_open_theta));

        %% measured impedance
        %Q = omega Cp Rp
        R_meas = Q ./ (omega * C_p);
        Z_meas = 1 ./ (1i * omega * C_p + 1 ./ R_meas);

        Z_corr = (Z_meas - Z_short) ./ (1 - (Z_meas - Z_short) / Z_open);
        C_compensated = real(1 ./ (1i * omega * Z_corr));
    end

end