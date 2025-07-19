classdef (Sealed) instrumentRack < handle
    % Thomas 20241221
    properties
        tryTimes (1, 1) double {mustBePositive} = inf;
        tryInterval (1, 1) duration = seconds(10);
        batchGetTimeout (1, 1) duration = seconds(5);
        batchSetTimeout (1, 1) duration = hours(2);
    end
    properties (SetAccess = private)
        instrumentTable = table(Size = [0, 3], ...
            VariableTypes = ["instrumentInterface", "string", "string"], ...
            VariableNames = ["instruments", "instrumentFriendlyNames", "addresses"]);
        channelTable = table(Size = [0, 8], ...
            VariableTypes = ["instrumentInterface", "string", "string", "string", "uint64", "double", "cell", "cell"], ...
            VariableNames = ["instruments", "instrumentFriendlyNames", "channels", "channelFriendlyNames", "channelSizes", "readDelays", "rampRates", "rampThresholds"]);
    end
    methods
        function obj = instrumentRack(skipDialog)
            arguments
                skipDialog logical = false;
            end
            assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");
            if ~skipDialog
                selection = questdlg("Is the sample safe?", "Check sample", "Yes", "No", "No");
                % Handle response
                if selection ~= "Yes"
                    error("instrumentRack construction cancelled by user.");
                end
            end
        end
        
        function addInstrument(obj, instrumentObj, instrumentFriendlyName)
            arguments
                obj
                instrumentObj (1, 1) instrumentInterface
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText}
            end
            
            % check for repetitions
            if ~isempty(obj.instrumentTable)
                assert(~any(instrumentObj == obj.instrumentTable.instruments), "Instrument must not repeat.")
                assert(~matches(instrumentFriendlyName, obj.instrumentTable.instrumentFriendlyNames), "Instrument friendly name must not repeat.")
            end
            
            obj.instrumentTable = [obj.instrumentTable; {instrumentObj, instrumentFriendlyName, instrumentObj.address}];
        end
        
        function addChannel(obj, instrumentFriendlyName, channel, channelFriendlyName, rampRates, rampThresholds)
            arguments
                obj;
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText};
                channel (1, 1) string {mustBeNonzeroLengthText};
                channelFriendlyName (1, 1) string {mustBeNonzeroLengthText};
                rampRates double {mustBePositive} = [];
                rampThresholds double {mustBePositive} = [];
            end
            
            % find instrument
            instrumentTableIndex = find(instrumentFriendlyName == obj.instrumentTable.instrumentFriendlyNames);
            assert(~isempty(instrumentTableIndex), "Instrument friendly name not found.");
            instrument = obj.instrumentTable.instruments(instrumentTableIndex);
            
            % find channel size
            channelSize = instrument.findChannelSize(channel);
            
            % validate rampRates size
            if isempty(rampRates)
                rampRates = inf(channelSize, 1);
            elseif isscalar(rampRates)
                rampRates = repmat(rampRates, channelSize, 1);
            else
                assert(numel(rampRates) == channelSize, "rampRates must be scalar or match channel size");
                if isrow(rampRates)
                    rampRates = rampRates.';
                end
            end
            % validate rampThresholds size
            if isempty(rampThresholds)
                rampThresholds = inf(channelSize, 1);
            elseif isscalar(rampThresholds)
                rampThresholds = repmat(rampThresholds, channelSize, 1);
            else
                assert(numel(rampThresholds) == channelSize, "rampThresholds must be scalar or match channel size");
                if isrow(rampThresholds)
                    rampThresholds = rampThresholds.';
                end
            end
            
            % test run to make sure channel is initialized before timing
            % response time
            instrument.getChannel(channel);
            
            % obtain response time of getRead over a few trials
            readDelayArray = nan(5, 1);
            trials = 5;
            for tryIndex = 1:trials
                instrument.getWriteChannel(channel);
                startTime = tic;
                instrument.getReadChannel(channel);
                readDelayArray(tryIndex) = toc(startTime);
            end
            readDelay = median(readDelayArray);

            newTable = [obj.channelTable; {instrument, instrumentFriendlyName, channel, channelFriendlyName, channelSize, readDelay, {rampRates}, {rampThresholds}}];
            
            % check for repetitions
            if ~isempty(obj.channelTable)
                assert(~matches(channelFriendlyName, obj.channelTable.channelFriendlyNames), "Channel friendly name must not repeat.");
                subTable = newTable(:, [1, 3]);
                assert(height(subTable) == height(unique(subTable)), "Channels must not repeat.");
            end
            obj.channelTable = newTable;
        end
        
        function values = rackGet(obj, channelFriendlyNames)
            arguments
                obj;
                channelFriendlyNames string {mustBeNonzeroLengthText, mustBeVector};
            end
            
            getTableFull = obj.subTableFromChannelFriendlyNames(channelFriendlyNames);
            
            % Add originalIndex column to track original positions
            getTableFull.originalIndex = (1:height(getTableFull)).';
            
            % Attach values column: initialize as cell array of nan arrays
            getTableFull.getValues = cell(height(getTableFull), 1);
            
            % sort descending based on response time
            getTableFull = sortrows(getTableFull, "readDelays", "descend");
            
            tries = 0;
            while tries < obj.tryTimes
                getTableRemaining = getTableFull;
                try
                    startTime = datetime("now");
                    while ~isempty(getTableRemaining)
                        assert(datetime("now") - startTime < obj.batchGetTimeout, "Timed out while performing batch get.");
                        
                        % get a batch of channels with different instruments
                        [~, uniqueIndices, ~] = unique(getTableRemaining.instruments, "stable");
                        batchTable = getTableRemaining(uniqueIndices, :);
                        getTableRemaining(uniqueIndices, :) = [];
                        
                        % first to write is last to read
                        for batchIndex = 1:height(batchTable)
                            batchTable.instruments(batchIndex).getWriteChannel(batchTable.channels(batchIndex));
                        end
                        for batchIndex = height(batchTable):-1:1
                            instrument = batchTable.instruments(batchIndex);
                            channel = batchTable.channels(batchIndex);
                            getValues = instrument.getReadChannel(channel);
                            % Store values back in the correct position in getTableFull
                            originalIndex = batchTable.originalIndex(batchIndex);
                            getTableFull.getValues{originalIndex} = getValues;
                        end
                    end
                    % Concatenate all values in order
                    values = vertcat(getTableFull.getValues{:});
                    break;
                catch ME
                    tries = tries + 1;
                    if tries >= obj.tryTimes
                        obj.dispLine()
                        obj.dispTime()
                        warning("An error occured during rackGet");
                        rethrow(ME);
                    else
                        obj.dispLine()
                        obj.dispTime()
                        warning("An error occured during rackGet");
                        disp(getReport(ME, "extended"));
                        obj.dispTime()
                        obj.dispLine()
                    end
                    if obj.tryInterval > 0
                        pause(seconds(obj.tryInterval));
                    end
                end
            end
        end
        
        function rackSetWrite(obj, channelFriendlyNames, values)
            arguments
                obj;
                channelFriendlyNames string {mustBeNonzeroLengthText, mustBeVector};
                values double {mustBeVector};
            end
            
            % Enforce column vector
            if ~isscalar(values) && isrow(values)
                values = values.';
            end
            
            batchTable = obj.subTableFromChannelFriendlyNames(channelFriendlyNames);
            
            % check length of values
            assert(sum(batchTable.channelSizes) == length(values), "Expected length %d, got length %d in the set values instead.", sum(batchTable.channelSizes), length(values));
            
            % Attach values column: slice values for each channel
            batchTable.setValues = cell(height(batchTable), 1);
            startIndex = 1;
            for i = 1:height(batchTable)
                channelSize = batchTable.channelSizes(i);
                batchTable.setValues{i} = values(startIndex : (startIndex + channelSize - 1));
                startIndex = startIndex + channelSize;
            end
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    obj.rackSetWriteHelper(batchTable);
                    break;
                catch ME
                    tries = tries + 1;
                    if tries >= obj.tryTimes
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        rethrow(ME);
                    else
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        disp(getReport(ME,"extended"));
                    end
                    if obj.tryInterval > 0
                        pause(seconds(obj.tryInterval));
                    end
                end
            end
        end
        
        function rackSet(obj, channelFriendlyNames, values)
            arguments
                obj;
                channelFriendlyNames string {mustBeNonzeroLengthText, mustBeVector};
                values double {mustBeVector};
            end
            
            % Enforce column vector
            if ~isscalar(values) && isrow(values)
                values = values.';
            end
            
            batchTableCopy = obj.subTableFromChannelFriendlyNames(channelFriendlyNames);
            
            % check length of values
            assert(sum(batchTableCopy.channelSizes) == length(values), "Expected length %d, got length %d in the set values instead.", sum(batchTableCopy.channelSizes), length(values));
            
            % Attach values column: slice values for each channel
            batchTableCopy.setValues = cell(height(batchTableCopy), 1);
            startIndex = 1;
            for i = 1:height(batchTableCopy)
                channelSize = batchTableCopy.channelSizes(i);
                batchTableCopy.setValues{i} = values(startIndex : (startIndex + channelSize - 1));
                startIndex = startIndex + channelSize;
            end
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    batchTable = batchTableCopy;
                    obj.rackSetWriteHelper(batchTable);
                    
                    startTime = datetime("now");
                    TFs = obj.rackVectorSetCheckHelper(batchTable);
                    while ~all(TFs)
                        assert(datetime("now") - startTime < obj.batchSetTimeout, "Timed out while performing batch set.");
                        batchTable = batchTable(~TFs, :);
                        TFs = obj.rackVectorSetCheckHelper(batchTable);
                    end
                    break;
                catch ME
                    tries = tries + 1;
                    if tries >= obj.tryTimes
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        rethrow(ME);
                    else
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        disp(getReport(ME,"extended"));
                    end
                    if obj.tryInterval > 0
                        pause(seconds(obj.tryInterval));
                    end
                end
            end
        end
        
        function TF = rackSetCheck(obj, channelFriendlyNames)
            % returns a scalar logical
            arguments
                obj;
                channelFriendlyNames string {mustBeNonzeroLengthText, mustBeVector};
            end
            
            batchTable = obj.subTableFromChannelFriendlyNames(channelFriendlyNames);
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    TF = obj.rackSetCheckHelper(batchTable);
                    break;
                catch ME
                    tries = tries + 1;
                    if tries >= obj.tryTimes
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        rethrow(ME);
                    else
                        obj.dispTime()
                        warning("An error occured during rackSetWrite");
                        disp(getReport(ME,"extended"));
                    end
                    if obj.tryInterval > 0
                        pause(seconds(obj.tryInterval));
                    end
                end
            end
        end
        
        function disp(obj)
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
            fprintf("<strong> Settings: </strong>\n")
            propertyNames = string({metaclass(obj).PropertyList.Name});
            setAccess = string({metaclass(obj).PropertyList.SetAccess});
            propertyNames = propertyNames(setAccess == "public");
            for propertyName = propertyNames
                fprintf("%s = %s\n", propertyName, string(obj.(propertyName)));
            end
            obj.dispLine();
            tempInstrumentTable = obj.instrumentTable(:, 2:end);
            tempInstrumentTable.Properties.VariableNames(1) = "instruments";
            disp(tempInstrumentTable);
            obj.dispLine();
            tempChannelTable = obj.channelTable(:, 2:end);
            tempChannelTable.Properties.VariableNames(1) = "instruments";
            tempChannelTable.rampRates = cellfun(@(x) x.', tempChannelTable.rampRates, UniformOutput = false);
            tempChannelTable.rampThresholds = cellfun(@(x) x.', tempChannelTable.rampThresholds, UniformOutput = false);
            disp(tempChannelTable);
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
        end
        
        function dummy(obj)
            % for copy pasting
            tries = 0;
            while tries < obj.tryTimes
                try
                catch ME %#ok<UNRCH>
                    tries = tries + 1;
                    if tries >= obj.tryTimes
                        obj.dispTime()
                        warning("An error occured during rackGet");
                        rethrow(ME);
                    else
                        obj.dispTime()
                        warning("An error occured during rackGet");
                        disp(getReport(ME,"extended"));
                    end
                    if obj.tryInterval > 0
                        pause(seconds(obj.tryInterval));
                    end
                end
            end
        end
        
    end
    
    methods (Access = private)
        
        function channelIndices = findChannelIndices(obj, channelFriendlyNames)
            
            numFriendlyNames = length(channelFriendlyNames);
            channelIndices = nan(numFriendlyNames, 1);
            for friendlyNameIndex = 1:numFriendlyNames
                channelFriendlyName = channelFriendlyNames(friendlyNameIndex);
                channelIndex = find(channelFriendlyName == obj.channelTable.channelFriendlyNames);
                assert(~isempty(channelIndex), "%s is not found in the rack.", channelFriendlyName);
                channelIndices(friendlyNameIndex) = channelIndex;
            end
            
        end
        
        function rackSetWriteHelperNoRamp(~, batchTable)
            for batchIndex = 1:height(batchTable)
                instrument = batchTable.instruments(batchIndex);
                channel = batchTable.channels(batchIndex);
                setValues = batchTable.setValues{batchIndex};
                instrument.setWriteChannel(channel, setValues);
            end
        end
        
        function rackSetWriteHelper(obj, batchTable)
            % Parallel ramping for all channels in batchTable, table-style
            setTable = batchTable;
            numRows = height(setTable);
            % Identify rows with inf rampRate (instant set)
            isInstant = false(numRows, 1);
            for i = 1:numRows
                if all(isinf(setTable.rampRates{i}))
                    isInstant(i) = true;
                end
            end
            % Instantly set those channels
            if any(isInstant)
                instantTable = setTable(isInstant, :);
                obj.rackSetWriteHelperNoRamp(instantTable);
                setTable(isInstant, :) = [];
            end
            if isempty(setTable)
                return;
            end
            % Attach startValues and reachedTargets columns
            setTable.startValues = cell(height(setTable), 1);
            setTable.reachedTargets = cell(height(setTable), 1);
            
            % Initialize startValues and reachedTargets
            isInstant = false(height(setTable), 1);
            for i = 1:height(setTable)
                setTable.startValues{i} = setTable.instruments(i).getChannel(setTable.channels(i));
                setValues = setTable.setValues{i};
                startValues = setTable.startValues{i};
                rampThresholds = setTable.rampThresholds{i};
                deltas = abs(setValues - startValues);
                % Mark as reached if delta is within rampThreshold
                setTable.reachedTargets{i} = false(size(startValues));
                % Mark for immediate set if all elements have delta > rampThreshold
                if all(deltas < rampThresholds)
                    isInstant(i) = true;
                end
            end
            % Immediately set those channels and remove from setTable
            if any(isInstant)
                immediateTable = setTable(isInstant, :);
                obj.rackSetWriteHelperNoRamp(immediateTable);
                setTable(isInstant, :) = [];
            end
            if isempty(setTable)
                return;
            end
            % Record start time
            startTime = datetime("now");
            % Main ramping loop
            while ~isempty(setTable)
                rampStepSetValues = cell(height(setTable), 1);
                allReached = false(height(setTable), 1); % Track which rows are done this step
                % Calculate total elapsed time
                nowTime = datetime("now");
                totalElapsed = seconds(nowTime - startTime);
                for i = 1:height(setTable)
                    startValues = setTable.startValues{i};
                    setValues = setTable.setValues{i};
                    rampRates = setTable.rampRates{i};
                    rampThresholds = setTable.rampThresholds{i};
                    reachedTargets = setTable.reachedTargets{i};
                    deltas = setValues - startValues;
                    signs = sign(deltas);
                    needRamp = ~reachedTargets;
                    % Calculate position based on total elapsed time
                    if totalElapsed == 0
                        % Initial step: use rampThresholds as step size
                        rampDistance = rampThresholds;
                    else
                        rampDistance = rampRates * totalElapsed;
                    end
                    % Calculate new step values
                    rampStepSetValues{i} = setValues;
                    if any(needRamp)
                        rampStepSetValues{i}(needRamp) = startValues(needRamp) + signs(needRamp) .* rampDistance(needRamp);
                    end
                    % Check if step would reach or overshoot target
                    overshoot = needRamp & (rampDistance >= abs(deltas));
                    if any(overshoot)
                        rampStepSetValues{i}(overshoot) = setValues(overshoot);
                    end
                    % Update reachedTargets flags
                    setTable.reachedTargets{i}(overshoot) = true;
                    % If all elements have reached target after this step, mark for removal
                    if all(setTable.reachedTargets{i})
                        allReached(i) = true;
                    end
                end
                setTableStep = setTable;
                setTableStep.setValues = rampStepSetValues;
                % execute the set
                obj.rackSetWriteHelperNoRamp(setTableStep);
                % Remove rows where all elements have reached target from setTable
                setTable(allReached, :) = [];
                if ~isempty(setTable)
                    pause(0.25); % avoid busy-waiting
                end
            end
        end
        
        function TFs = rackVectorSetCheckHelper(~, batchTable)
            % returns logical column vector of the same height as batchTable
            TFs = false(height(batchTable), 1);
            for batchIndex = 1:height(batchTable)
                instrument = batchTable.instruments(batchIndex);
                channel = batchTable.channels(batchIndex);
                TF = instrument.setCheckChannel(channel);
                assert(isscalar(TF), "setCheckChannel should return a scalar logical, received length %d instead", length(TF));
                TFs(batchIndex) = TF;
            end
        end
        
        function TF = rackSetCheckHelper(~, batchTable)
            % returns a scalar logical indicating if all channels have reached their target
            for batchIndex = 1:height(batchTable)
                instrument = batchTable.instruments(batchIndex);
                channel = batchTable.channels(batchIndex);
                TF = instrument.setCheckChannel(channel);
                assert(isscalar(TF), "setCheckChannel should return a scalar logical, received length %d instead", length(TF));
                if ~TF
                    return;
                end
            end
            TF = true;
        end
        
        function subTable = subTableFromChannelFriendlyNames(obj, channelFriendlyNames)
            channelIndices = obj.findChannelIndices(channelFriendlyNames);
            subTable = obj.channelTable(channelIndices, :);
            % values column will be attached by caller (get/set) as needed
        end
        
    end
    methods (Static, Access = private)
        
        function dispLine()
            disp(join(repelem("=", 120), ""));
        end
        
        function dispTime()
            fprintf(string(datetime("now")) + "\n");
        end
        
    end
    
    
end