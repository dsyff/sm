classdef instrument_strainController < instrumentInterface
    % Persistent Strain Control System for SM1.5
    % Migrated from legacy persistent strain control v1.3
    % Implements parallel feedback control loop for strain cell manipulation
    % Thomas 2025-07-17
    
    properties (Access = private)
        % Physical instruments managed internally
        lcr          % E4980AL LCR meter
        voltageSrc_A % K2450_A outer PZT voltage source  
        voltageSrc_B % K2450_B inner PZT voltage source
        cryostat     % Montana2 or Opticool temperature controller
        
        % Parallel processing handles
        dog2Man      % Communication channel from worker to main thread
        man2Dog      % Communication channel from main to worker thread  
        dogFuture    % Future object for worker thread
        
        % Control state variables
        activeControl = false;
        parameterValues = struct();  % d_0, Z_short_r, Z_short_theta, etc.
        
        % Safety and monitoring
        cleanupObj   % Ensures graceful voltage ramp-down on error
        logFolder = "strain_logs";
    end
    
    methods
        
        function obj = instrument_strainController(options)
            arguments
                options.address_E4980AL (1, 1) string = "GPIB::6::INSTR";
                options.address_K2450_A (1, 1) string = "GPIB::17::INSTR";
                options.address_K2450_B (1, 1) string = "GPIB::18::INSTR";
                options.address_Montana2 (1, 1) string = "136.167.55.165";
                options.address_Opticool (1, 1) string = "127.0.0.1";
                options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "Opticool"])};
                options.strainCellNumber (1, 1) uint8 {mustBeInteger, mustBePositive};
            end
            
            obj@instrumentInterface();
            
            % Verify MATLAB version and parallel computing setup
            assert(~isMATLABReleaseOlderThan("R2022a"), "MATLAB R2022a or newer required for strain controller");
            obj.ensureParallelPool();
            
            % Create log directory
            if ~isfolder(obj.logFolder)
                mkdir(obj.logFolder);
            end
            
            % Start parallel strain control worker
            obj.startStrainWorker(options);
            
            % Add channels for SM1.5 integration
            % Note: SM1.5 will see these as regular channels, but reads/sets
            % are handled by the parallel worker via message passing
            obj.addChannel("del_d", setTolerances = 5e-9);     % Displacement (m)
            obj.addChannel("T", setTolerances = 0.1);          % Temperature (K)  
            obj.addChannel("Cp");                              % Parallel capacitance (F)
            obj.addChannel("Q");                               % Quality factor
            obj.addChannel("C");                               % Compensated capacitance (F)
            obj.addChannel("d");                               % Absolute displacement (m)
            obj.addChannel("V_str_o", setTolerances = 5e-3);   % Outer PZT voltage (V)
            obj.addChannel("V_str_i", setTolerances = 5e-3);   % Inner PZT voltage (V)
            obj.addChannel("I_str_o");                         % Outer PZT current (A)
            obj.addChannel("I_str_i");                         % Inner PZT current (A)
            obj.addChannel("activeControl", setTolerances = 0.1); % Control mode on/off
            
            obj.address = sprintf("strainController_%s", options.cryostat);
            
            % Setup safety cleanup
            obj.cleanupObj = onCleanup(@() obj.emergencyShutdown());
        end
        
        function delete(obj)
            % Gracefully shut down strain controller
            try
                obj.stopStrainWorker();
            catch ME
                warning('StrainController:ShutdownError', 'Error during strain controller shutdown: %s', ME.message);
            end
        end
        
        function setParameters(obj, varargin)
            % Set strain controller parameters (frequency, impedances, etc.)
            % Usage: obj.setParameters('d_0', value, 'frequency', 100e3, ...)
            
            % Convert to struct for worker
            params = struct(varargin{:});
            
            % Send to worker
            command.action = "SET_PARAMETERS";
            command.parameters = params;
            obj.sendCommand(command);
        end
        
        function tareDisplacement(obj, numSamples)
            % Perform tare operation to set d_0 reference
            arguments
                obj
                numSamples (1,1) double = 20
            end
            
            command.action = "TARE";
            command.numSamples = numSamples;
            result = obj.sendCommand(command);
            
            fprintf('Tare completed. d_0 = %.6e m\n', result.d_0);
        end
        
    end
    
    methods (Access = ?instrumentInterface)
        
        function getWriteChannelHelper(~, ~)
            % For strain controller, reads are always from cached values
            % No separate write phase needed since worker continuously updates
            % This maintains SM1.5 batch optimization compatibility
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Read channel values from strain worker
            
            channelNames = ["del_d", "T", "Cp", "Q", "C", "d", ...
                           "V_str_o", "V_str_i", "I_str_o", "I_str_i", "activeControl"];
            
            channel = channelNames(channelIndex);
            
            command.action = "GET";
            command.channel = channel;
            
            try
                getValues = obj.sendCommand(command, seconds(15));
            catch ME
                if contains(ME.message, "timeout")
                    error('Strain controller timeout reading %s. Check worker status.', channel);
                else
                    rethrow(ME);
                end
            end
        end
        
        function setWriteChannelHelper(obj, channelIndex, setValues)
            % Send set commands to strain worker
            
            channelNames = ["del_d", "T", "Cp", "Q", "C", "d", ...
                           "V_str_o", "V_str_i", "I_str_o", "I_str_i", "activeControl"];
            
            channel = channelNames(channelIndex);
            
            % Only certain channels are settable
            settableChannels = ["del_d", "T", "V_str_o", "V_str_i", "activeControl"];
            
            if ~ismember(channel, settableChannels)
                error('Channel %s is read-only for strain controller', channel);
            end
            
            command.action = "SET";
            command.channel = channel;
            command.value = setValues;
            
            % Send command and wait for completion
            obj.sendCommand(command, hours(3)); % Long timeout for strain settling
        end
        
    end
    
    methods (Access = private)
        
        function ensureParallelPool(~)
            % Ensure parallel pool is running for strain worker
            currentPool = gcp('nocreate');
            if isempty(currentPool) || currentPool.Busy
                evalc("delete(currentPool)");
                evalc("parpool('Processes', 2)");
            end
        end
        
        function startStrainWorker(obj, options)
            % Start parallel strain control worker thread
            
            obj.dog2Man = parallel.pool.PollableDataQueue;
            
            % Launch worker with all original functionality
            obj.dogFuture = parfeval(@obj.strainWorkerMain, 0, obj.dog2Man, options);
            
            % Wait for worker to initialize and send back man2Dog channel
            timeout = seconds(30);
            startTime = datetime("now");
            
            while obj.dog2Man.QueueLength == 0
                if ~matches(obj.dogFuture.State, "running")
                    if isprop(obj.dogFuture, 'Error') && ~isempty(obj.dogFuture.Error)
                        rethrow(obj.dogFuture.Error.remotecause{1});
                    else
                        error("Strain worker failed to start. State: %s", obj.dogFuture.State);
                    end
                end
                
                if datetime("now") - startTime > timeout
                    error("Strain worker initialization timeout");
                end
                
                pause(0.1);
            end
            
            obj.man2Dog = poll(obj.dog2Man);
            pause(2); % Allow worker to fully initialize
        end
        
        function stopStrainWorker(obj)
            % Gracefully stop strain worker
            if ~isempty(obj.man2Dog)
                try
                    command.action = "STOP";
                    obj.sendCommand(command, seconds(10));
                catch
                    % Force stop if graceful stop fails
                    if ~isempty(obj.dogFuture)
                        cancel(obj.dogFuture);
                    end
                end
            end
        end
        
        function reply = sendCommand(obj, command, timeout)
            % Send command to strain worker and wait for response
            arguments
                obj
                command struct
                timeout duration = seconds(5)
            end
            
            % Verify worker is still running
            if isempty(obj.dogFuture) || obj.dogFuture.State ~= "running"
                error("Strain worker is not running");
            end
            
            % Flush any old messages
            while obj.dog2Man.QueueLength > 0
                poll(obj.dog2Man);
            end
            
            % Send command
            send(obj.man2Dog, command);
            
            % Wait for response
            startTime = datetime("now");
            while obj.dog2Man.QueueLength == 0
                if ~matches(obj.dogFuture.State, "running")
                    if isprop(obj.dogFuture, 'Error') && ~isempty(obj.dogFuture.Error)
                        rethrow(obj.dogFuture.Error.remotecause{1});
                    else
                        error("Strain worker stopped unexpectedly");
                    end
                end
                
                if datetime("now") - startTime > timeout
                    error("Strain worker response timeout");
                end
                
                pause(0.01);
            end
            
            reply = poll(obj.dog2Man);
            
            % Handle error responses
            if isstring(reply) && startsWith(reply, "Error", "IgnoreCase", true)
                error(reply);
            elseif isa(reply, "MException")
                rethrow(reply);
            end
        end
        
        function emergencyShutdown(obj)
            % Emergency voltage ramp-down for safety
            try
                if ~isempty(obj.man2Dog)
                    command.action = "EMERGENCY_STOP";
                    send(obj.man2Dog, command);
                    pause(1);
                end
            catch
                warning('Emergency shutdown command failed - manual intervention may be required');
            end
        end
        
    end
    
    methods (Static, Access = private)
        
        function strainWorkerMain(dog2Man, options)
            % Main strain control worker function (runs on separate thread)
            % Contains all the original strainWatchdog.m logic
            
            %% settings
            % If last sampling is older than staleTime ago, and if activeControl is on,
            % get statements from smc receive error
            staleTime = seconds(2); %#ok<NASGU>
            dataChunkLength = 2^16;
            temperatureSafeMargin = 3; %K for determining max strain voltage
            voltageBoundFraction = 0.9; %- multiplied on computed min/max strain voltage

            %% pass back man2dog message channel
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
            oldData = []; %#ok<NASGU>
            unfilledDataRow = 1;
            V_str_o_max = nan;
            V_str_o_min = nan;
            V_str_i_max = nan;
            V_str_i_min = nan;
            justEndedActiveControl = false;
            rampToAnchor = true;
            branchNum = 0; %#ok<NASGU>
                
                %% Local function definitions (originally nested functions)
                function refreshDataTimetablesAndLoopVariables(throwAll)
                    recordChannels = ["Cp", "Q", "V_str_o", "I_str_o", "V_str_i", "I_str_i", "T", "C", "del_d", "del_d_target", "branchNum"];
                    nanArray = nan(dataChunkLength, length(recordChannels));
                    natArray = NaT(dataChunkLength, 1);
                    newTimetable = array2timetable(nanArray, RowTimes = natArray, VariableNames = recordChannels);

                    if throwAll
                        % turning off activeControl
                        saveDataTimetable(currentData);
                        oldData = [];
                        currentData = newTimetable;
                    elseif isempty(currentData)
                        % when turning on activeControl for the first time
                        currentData = newTimetable;
                    else
                        % currentData is full
                        saveDataTimetable(currentData);
                        oldData = currentData;
                        currentData = newTimetable;
                    end
                    unfilledDataRow = 1;
                end

                function saveDataTimetable(dataTimetable)
                    dataTimetableFolder = "strain_data";
                    if ~isfolder(dataTimetableFolder)
                        mkdir(dataTimetableFolder);
                    end
                    saveFilename = dataTimetableFolder + filesep + string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
                    save(saveFilename + ".mat", "dataTimetable");
                    save(saveFilename + ".mat", "-fromstruct", parameterVariables, "-append");
                    save(saveFilename + ".mat", "-fromstruct", activeControlVariableSetValues, "-append");
                    save(saveFilename + ".mat", "-fromstruct", alwaysControlVariableSetValues, "-append");
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
                
                function displacement = C2d(capacitance)
                    % conversion from capacitance to displacement
                    if options.strainCellNumber == 1
                        C_0 = 0.01939E-12;
                        alpha = 55.963E-18;
                    elseif options.strainCellNumber == 2
                        C_0 = 0.01394E-12;
                        alpha = 57.058E-18;
                    else
                        error("Unsupported strain cell number: %d", options.strainCellNumber);
                    end
                    displacement = alpha ./ (capacitance - C_0);
                end
            
            
            %% initialize instruments
            rack_strain = instrumentRack(true);
            rack_strain.tryTimes = inf;
            
            %% E4980AL LCR meter
            handle_E4980AL = instrument_E4980AL(options.address_E4980AL);
            rack_strain.addInstrument(handle_E4980AL, "E4980AL");
            rack_strain.addChannel("E4980AL", "Cp", "Cp");
            rack_strain.addChannel("E4980AL", "Q", "Q");
            rack_strain.addChannel("E4980AL", "CpQ", "CpQ");

            %% Cryostat (Montana2 or Opticool)
            if options.cryostat == "Montana2"
                handle_cryostat = instrument_Montana2(options.address_Montana2);
                rack_strain.addInstrument(handle_cryostat, "Montana2");
                rack_strain.addChannel("Montana2", "T", "T");
            elseif options.cryostat == "Opticool"
                handle_cryostat = instrument_Opticool(options.address_Opticool);
                rack_strain.addInstrument(handle_cryostat, "Opticool");
                rack_strain.addChannel("Opticool", "T", "T");
            end

            %% K2450_A (outer PZT voltage source)
            handle_K2450_A = instrument_K2450(options.address_K2450_A);
            h = handle_K2450_A.communicationHandle;
            writeline(h,":sense:current:range 1e-7");
            writeline(h,"source:voltage:Ilimit 8e-8");
            writeline(h,":source:voltage:range 200");
            writeline(h,":OUTP ON");
            writeline(h,"NPLcycles 0.2"); %number of power line cycles per measurement

            pause(2);
            handle_K2450_A.chargeCurrentLimit = 1E-7;
            handle_K2450_A.setSetTolerances("V_source", 5E-3);
            rack_strain.addInstrument(handle_K2450_A, "K2450_A");
            rack_strain.addChannel("K2450_A", "V_source", "V_str_o");
            rack_strain.addChannel("K2450_A", "I_measure", "I_str_o");
            rack_strain.addChannel("K2450_A", "VI", "VI_str_o");

            %% K2450_B (inner PZT voltage source)
            handle_K2450_B = instrument_K2450(options.address_K2450_B);
            h = handle_K2450_B.communicationHandle;
            writeline(h,":sense:current:range 1e-7");
            writeline(h,"source:voltage:Ilimit 5e-8");
            writeline(h,":source:voltage:range 200");
            writeline(h,":OUTP ON");
            writeline(h,"NPLcycles 0.2"); %number of power line cycles per measurement

            pause(2);
            handle_K2450_B.chargeCurrentLimit = 1E-7;
            handle_K2450_B.setSetTolerances("V_source", 5E-3);
            rack_strain.addInstrument(handle_K2450_B, "K2450_B");
            rack_strain.addChannel("K2450_B", "V_source", "V_str_i");
            rack_strain.addChannel("K2450_B", "I_measure", "I_str_i");
            rack_strain.addChannel("K2450_B", "VI", "VI_str_i");

            %% create cleanup object
            cleanupObj = onCleanup(@() rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]));

            %% create log directories
            logFolder = "strain_logs";
            if ~isfolder(logFolder)
                mkdir(logFolder);
            end

            %% get current target temperature
            alwaysControlVariableSetValues.T = handle_cryostat.getCurrentTargetTemperature();

            %% set del_d target
            activeControlVariableSetValues.del_d = 0;

            %% refresh data structures  
            refreshDataTimetablesAndLoopVariables(false);

            %% Command processing function
                function response = processCommand(command)
                    try
                        switch command.action
                            case "GET"
                                response = getVariable(command.channel);
                            case "SET"
                                setVariable(command.channel, command.value);
                                response = "OK";
                            case "SET_PARAMETERS"
                                setParameters(command.parameters);
                                response = "OK";
                            case "TARE"
                                response = performTare(command.numSamples);
                            case "STOP"
                                keepAlive = false;
                                response = "STOPPING";
                            case "EMERGENCY_STOP"
                                emergencyRampDown();
                                response = "EMERGENCY_COMPLETE";
                            otherwise
                                response = "Error: Unknown command";
                        end
                    catch ME
                        response = ME;
                    end
                end
                
                function value = getVariable(channel)
                    switch channel
                        case "del_d"
                            value = activeControlVariables.del_d;
                        case "T"
                            value = alwaysControlVariables.T;
                        case "Cp"
                            value = readOnlyVariables.Cp;
                        case "Q"
                            value = readOnlyVariables.Q;
                        case "C"
                            value = readOnlyVariables.C;
                        case "d"
                            value = readOnlyVariables.d;
                        case "V_str_o"
                            value = directControlVariables.V_str_o;
                        case "V_str_i"
                            value = directControlVariables.V_str_i;
                        case "I_str_o"
                            value = readOnlyVariables.I_str_o;
                        case "I_str_i"
                            value = readOnlyVariables.I_str_i;
                        case "activeControl"
                            value = activeControl;
                        otherwise
                            error("Unknown channel: %s", channel);
                    end
                end
                
                function setVariable(channel, value)
                    switch channel
                        case "del_d"
                            activeControlVariableSetValues.del_d = value;
                        case "T"
                            alwaysControlVariableSetValues.T = value;
                        case "V_str_o"
                            if ~activeControl
                                rack_strain.rackSetWrite("V_str_o", value);
                            else
                                error("Cannot set V_str_o directly when activeControl is on");
                            end
                        case "V_str_i"
                            if ~activeControl
                                rack_strain.rackSetWrite("V_str_i", value);
                            else
                                error("Cannot set V_str_i directly when activeControl is on");
                            end
                        case "activeControl"
                            if logical(value) ~= activeControl
                                if logical(value)
                                    % Turning on activeControl - validate parameters
                                    for channel_param = string(fieldnames(parameterVariables)).'
                                        if isnan(parameterVariables.(channel_param))
                                            error("Parameter %s has not been set.", channel_param);
                                        end
                                    end
                                    if isnan(activeControlVariableSetValues.del_d)
                                        error("Channel del_d has not been set.");
                                    end
                                    if isnan(alwaysControlVariableSetValues.T)
                                        error("Channel T has not been set.");
                                    end
                                    % Log parameters when starting activeControl
                                    logParameterVariables();
                                else
                                    % Turning off activeControl
                                    justEndedActiveControl = true;
                                end
                                activeControl = logical(value);
                            end
                        otherwise
                            error("Channel %s is not settable", channel);
                    end
                end
                
                function logParameterVariables()
                    saveFilename = logFolder + filesep + string(datetime("now", Format = "yyyyMMdd_HHmmss_SSS"));
                    save(saveFilename + ".mat", "-struct", "parameterVariables");
                end
                
                function setParameters(params)
                    if activeControl
                        error("Cannot set parameters while activeControl is on");
                    end
                    
                    fields = fieldnames(params);
                    for i = 1:length(fields)
                        field = fields{i};
                        parameterVariables.(field) = params.(field);
                    end
                end
                
                function result = performTare(numSamples)
                    if activeControl
                        error("Cannot perform tare while activeControl is on");
                    end
                    
                    % Validate that required parameters are set
                    for channel_param = string(fieldnames(parameterVariables)).'
                        if channel_param ~= "d_0" && isnan(parameterVariables.(channel_param))
                            error("Parameter %s has not been set.", channel_param);
                        end
                    end
                    
                    % Take multiple samples and average
                    values = nan(numSamples, 1);
                    for i = 1:numSamples
                        data = rack_strain.rackGet("CpQ");
                        Cp = data(1);
                        Q = data(2);
                        C = C_comp(Cp, Q);
                        d = C2d(C);
                        values(i) = d;
                        pause(0.1);
                    end
                    
                    % Use median with outlier removal like in legacy code
                    d_0 = median(rmoutliers(values));
                    parameterVariables.d_0 = d_0;
                    
                    % Store tare data for diagnostics
                    tareData.d_0 = d_0;
                    tareData.values = values;
                    
                    result.d_0 = parameterVariables.d_0;
                    result.values = values;
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

                function emergencyRampDown()
                    try
                        rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
                    catch
                        % If rack operation fails, try individual instruments
                        try
                            handle_K2450_A.setChannel("V_source", 0);
                        catch
                        end
                        try
                            handle_K2450_B.setChannel("V_source", 0);
                        catch
                        end
                    end
                    keepAlive = false;
                end

                %% Main control loop
                % without try/catch, matlab sometimtes fails to handle error here correctly
                % and instead restarts the worker with no warning
                try
                    while keepAlive
                        % Process commands from main thread
                        while man2Dog.QueueLength > 0
                            command = poll(man2Dog);
                            response = processCommand(command);
                            send(dog2Man, response);
                        end
                        
                        % Execute strain control logic
                        if activeControl
                            % React to target changes
                            if del_d_target ~= activeControlVariableSetValues.del_d
                                del_d_target = activeControlVariableSetValues.del_d;
                            end
                            if T_target ~= alwaysControlVariableSetValues.T
                                T_target = alwaysControlVariableSetValues.T;
                                rack_strain.rackSetWrite("T", T_target);
                            end

                            % Update current values
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

                            % PID control logic - full implementation from legacy code
                            del_V_str_o_max = abs(directControlVariables.V_str_o - V_str_o_max);
                            del_V_str_o_min = abs(directControlVariables.V_str_o - V_str_o_min);
                            del_V_str_i_0 = abs(directControlVariables.V_str_i - 0);

                            % check if voltages reached limit of previous time step
                            V_str_o_reached = abs(readOnlyVariables.I_str_o) < 1E-7;
                            V_str_i_reached = abs(readOnlyVariables.I_str_i) < 1E-7;
                            V_str_o_reached_max = V_str_o_reached && del_V_str_o_max < 5E-3;
                            V_str_i_reached_max = V_str_i_reached && abs(directControlVariables.V_str_i - V_str_i_max) < 5E-3;
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
                                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_max, V_str_i_max]);
                                    branchNum = 1;
                                elseif V_str_i_reached_zero
                                    rack_strain.rackSetWrite("V_str_o", V_str_o_max);
                                    branchNum = 2;
                                elseif V_str_o_reached_min
                                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_min, 0]);
                                    branchNum = 3;
                                else
                                    rampToAnchor = true;
                                    branchNum = 4;
                                end
                            else
                                if V_str_o_reached_min
                                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_min, V_str_i_min]);
                                    branchNum = 5;
                                elseif V_str_i_reached_zero
                                    rack_strain.rackSetWrite("V_str_o", V_str_o_min);
                                    branchNum = 6;
                                elseif V_str_o_reached_max
                                    rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [V_str_o_max, 0]);
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
                                    rack_strain.rackSetWrite("V_str_o", V_str_o_target);
                                end
                                if ~isnan(V_str_i_target)
                                    rack_strain.rackSetWrite("V_str_i", V_str_i_target);
                                end
                            end

                            % add new entry to data timetable
                            if ~isempty(currentData)
                                currentData(unfilledDataRow, :) = num2cell([getValues.', ...
                                    readOnlyVariables.C, activeControlVariables.del_d, del_d_target, branchNum]);
                                currentData.Time(unfilledDataRow) = lastUpdate;

                                if unfilledDataRow == dataChunkLength
                                    refreshDataTimetablesAndLoopVariables(false);
                                else
                                    unfilledDataRow = unfilledDataRow + 1;
                                end
                            end
                        
                        else
                            if justEndedActiveControl
                                rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
                                refreshDataTimetablesAndLoopVariables(true);
                                justEndedActiveControl = false;
                            end
                            
                            % Not in active control - just read current values
                            try
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
                                if ~isnan(parameterVariables.d_0)
                                    activeControlVariables.del_d = readOnlyVariables.d - parameterVariables.d_0;
                                end
                                alwaysControlVariables.T = getValues(7);
                            catch ME
                                % If measurements fail, continue loop
                                fprintf('Measurement error: %s\n', ME.message);
                            end
                        end
                    
                    % This pause is here to ensure this while loop can be interrupted. This
                    % causes negligible slowdown.
                    pause(1E-5);
                    end
                
                % Final cleanup when exiting normally
                rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
                
                catch ME
                    % Emergency cleanup and error propagation
                    try
                        % Try to save any current data
                        if exist('currentData', 'var') && ~isempty(currentData)
                            saveDataTimetable(currentData);
                        end
                        % Emergency ramp down
                        if exist('rack_strain', 'var')
                            rack_strain.rackSetWrite(["V_str_o", "V_str_i"], [0, 0]);
                        end
                    catch
                        % If rack fails, try individual instruments
                        try
                            if exist('handle_K2450_A', 'var')
                                handle_K2450_A.setChannel("V_source", 0);
                            end
                        catch
                        end
                        try
                            if exist('handle_K2450_B', 'var')
                                handle_K2450_B.setChannel("V_source", 0);
                            end
                        catch
                        end
                    end
                    % Re-throw the error after cleanup
                    rethrow(ME);
                end
        end
        
    end
    
end
