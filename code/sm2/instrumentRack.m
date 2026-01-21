classdef (Sealed) instrumentRack < handle
    % Thomas 20241221
    properties
        tryTimes (1, 1) double {mustBePositive} = inf;
        tryInterval (1, 1) duration = minutes(10);
        batchGetTimeout (1, 1) duration = seconds(20);
        batchSetTimeout (1, 1) duration = hours(3);
    end
    properties (SetAccess = private)
        instrumentTable = table(Size = [0, 4], ...
            VariableTypes = ["instrumentInterface", "string", "string", "logical"], ...
            VariableNames = ["instruments", "instrumentFriendlyNames", "addresses", "virtual"]);
        channelTable = table(Size = [0, 11], ...
            VariableTypes = ["instrumentInterface", "string", "string", "string", "uint64", "double", "cell", "cell", "cell", "cell", "logical"], ...
            VariableNames = ["instruments", "instrumentFriendlyNames", "channels", "channelFriendlyNames", "channelSizes", "readDelays", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs", "virtual"]);
    end
    properties (Access = private)
        isBatchGetActive logical = false;
    end
    methods
        function obj = instrumentRack(skipDialog)
            arguments
                skipDialog logical = false;
            end
            assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");
            if ~skipDialog
                selection = questdlg( ...
                    "Has Windows Update been postponed, and is the sample safe?", ...
                    "Preflight Checks", "Yes", "No", "No");
                if selection ~= "Yes"
                    error("instrumentRack construction cancelled by user.");
                end
            end
        end
        
        function delete(obj)
            if ~isempty(obj.instrumentTable)
                instruments = obj.instrumentTable.instruments;
                names = obj.instrumentTable.instrumentFriendlyNames;
                for idx = 1:numel(instruments)
                    instrument = instruments(idx);
                    friendlyName = char(names(idx));
                    if isvalid(instrument)
                        try
                            delete(instrument);
                        catch ME
                            fprintf("instrumentRack delete warning: failed to delete instrument %s: %s\n", friendlyName, ME.message);
                        end
                    end
                end
            end
            obj.instrumentTable = obj.instrumentTable([], :);
            obj.channelTable = obj.channelTable([], :);
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

            % Ensure the instrument comms buffer starts clean.
            % Default implementation is a no-op; real instruments may override.
            try
                instrumentObj.flush();
            catch ME
                warning("instrumentRack:addInstrumentFlushFailed", ...
                    "Failed to flush instrument %s (%s) during addInstrument. Continuing. Error: %s", ...
                    instrumentFriendlyName, instrumentObj.address, ME.message);
            end

            isVirtualInstrument = isa(instrumentObj, "virtualInstrumentInterface");
            obj.instrumentTable = [obj.instrumentTable; {instrumentObj, instrumentFriendlyName, instrumentObj.address, isVirtualInstrument}];
        end
        
        function addChannel(obj, instrumentFriendlyName, channel, channelFriendlyName, rampRates, rampThresholds, softwareMins, softwareMaxs)
            arguments
                obj;
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText};
                channel (1, 1) string {mustBeNonzeroLengthText};
                channelFriendlyName (1, 1) string {mustBeNonzeroLengthText};
                rampRates double {mustBePositive} = [];
                rampThresholds double {mustBePositive} = [];
                softwareMins double = [];
                softwareMaxs double = [];
            end
            
            % find instrument
            instrumentTableIndex = find(instrumentFriendlyName == obj.instrumentTable.instrumentFriendlyNames);
            assert(~isempty(instrumentTableIndex), "Instrument friendly name not found.");
            instrument = obj.instrumentTable.instruments(instrumentTableIndex);
            instrumentVirtualFlag = obj.instrumentTable.virtual(instrumentTableIndex);
            
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
            
            % validate software limits size
            if isempty(softwareMins)
                softwareMins = -inf(channelSize, 1);
            elseif isscalar(softwareMins)
                softwareMins = repmat(softwareMins, channelSize, 1);
            else
                assert(numel(softwareMins) == channelSize, "softwareMins must be scalar or match channel size");
                if isrow(softwareMins)
                    softwareMins = softwareMins.';
                end
            end
            
            if isempty(softwareMaxs)
                softwareMaxs = inf(channelSize, 1);
            elseif isscalar(softwareMaxs)
                softwareMaxs = repmat(softwareMaxs, channelSize, 1);
            else
                assert(numel(softwareMaxs) == channelSize, "softwareMaxs must be scalar or match channel size");
                if isrow(softwareMaxs)
                    softwareMaxs = softwareMaxs.';
                end
            end
            
            assert(all(softwareMins <= softwareMaxs), "Software limits must satisfy min <= max for every element.");
            
            if instrumentVirtualFlag
                readDelay = NaN;
            else
                try
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
                catch ME
                    obj.dispLine()
                    obj.dispTime()
                    fprintf("Failed to read %s/%s.\n", instrumentFriendlyName, channel);
                    obj.dispPartialStackTrace(ME);
                    obj.dispTime()
                    obj.dispLine()
                    readDelay = inf;
                end
            end
            
            newTable = [obj.channelTable; {instrument, instrumentFriendlyName, channel, channelFriendlyName, channelSize, readDelay, {rampRates}, {rampThresholds}, {softwareMins}, {softwareMaxs}, instrumentVirtualFlag}];
            
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
            
            assert(~obj.isBatchGetActive, "instrumentRack:ActiveBatchGet", ...
                "Cannot call rackGet while a batch get is already in progress.");
            
            % sort descending based on response time
            getTableFull = sortrows(getTableFull, "readDelays", "descend");
            
            physicalMask = ~getTableFull.virtual;
            virtualMask = getTableFull.virtual;

            tries = 0;
            while tries < obj.tryTimes
                try
                    getTableFull.getValues = cell(height(getTableFull), 1);

                    if any(physicalMask)
                        lockGuard = obj.activateBatchGetLock(); %#ok<NASGU>
                        getTableRemaining = getTableFull(physicalMask, :);
                        startTime = datetime("now");
                        while ~isempty(getTableRemaining)
                            assert(datetime("now") - startTime < obj.batchGetTimeout, "Timed out while performing batch get.");
                            
                            % get a batch of channels with different instruments
                            [~, uniqueIndices, ~] = unique(getTableRemaining.instruments, "stable");
                            batchTable = getTableRemaining(uniqueIndices, :);
                            getTableRemaining(uniqueIndices, :) = [];

                            % first to write is last to read
                            % If an error occurs mid-batch, some instruments may have
                            % pending unread responses; flush them before retrying.
                            pendingInstruments = instrumentInterface.empty(0, 1);
                            try
                                for batchIndex = 1:height(batchTable)
                                    instrument = batchTable.instruments(batchIndex);
                                    channel = batchTable.channels(batchIndex);
                                    instrument.getWriteChannel(channel);
                                    pendingInstruments(end+1, 1) = instrument; %#ok<AGROW>
                                end
                                for batchIndex = height(batchTable):-1:1
                                    instrument = batchTable.instruments(batchIndex);
                                    channel = batchTable.channels(batchIndex);
                                    getValuesPartial = instrument.getReadChannel(channel);
                                    originalIndex = batchTable.originalIndex(batchIndex);
                                    getTableFull.getValues{originalIndex} = getValuesPartial;

                                    % Reads occur in reverse order of writes, so pending is a stack.
                                    if ~isempty(pendingInstruments)
                                        pendingInstruments(end) = [];
                                    end
                                end
                            catch MEBatch
                                obj.flushInstrumentsSafe(pendingInstruments, "rackGet batch cleanup before retry");
                                rethrow(MEBatch);
                            end
                        end
                        clear lockGuard;
                    end

                    if any(virtualMask)
                        for virtualIndex = find(virtualMask).'
                            instrument = getTableFull.instruments(virtualIndex);
                            channel = getTableFull.channels(virtualIndex);
                            virtualValues = instrument.getChannel(channel);
                            originalIndex = getTableFull.originalIndex(virtualIndex);
                            getTableFull.getValues{originalIndex} = virtualValues;
                        end
                    end

                    % Concatenate all values in order
                    values = vertcat(getTableFull.getValues{:});
                    break;
                catch ME
                    if exist('lockGuard', 'var')
                        clear lockGuard;
                    end
                    tries = tries + 1;
                    obj.handleRetryError(ME, "rackGet", tries);
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
                rawValues = values(startIndex : (startIndex + channelSize - 1));
                minLimits = batchTable.softwareMins{i};
                maxLimits = batchTable.softwareMaxs{i};
                batchTable.setValues{i} = obj.enforceSoftwareLimits(rawValues, minLimits, maxLimits);
                startIndex = startIndex + channelSize;
            end
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    obj.rackSetWriteHelper(batchTable);
                    break;
                catch ME
                    tries = tries + 1;
                    obj.handleRetryError(ME, "rackSetWrite", tries);
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
                rawValues = values(startIndex : (startIndex + channelSize - 1));
                minLimits = batchTableCopy.softwareMins{i};
                maxLimits = batchTableCopy.softwareMaxs{i};
                batchTableCopy.setValues{i} = obj.enforceSoftwareLimits(rawValues, minLimits, maxLimits);
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
                    obj.handleRetryError(ME, "rackSetWrite", tries);
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
                    obj.handleRetryError(ME, "rackSetWrite", tries);
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
            tempChannelTable.softwareMins = cellfun(@(x) x.', tempChannelTable.softwareMins, UniformOutput = false);
            tempChannelTable.softwareMaxs = cellfun(@(x) x.', tempChannelTable.softwareMaxs, UniformOutput = false);
            disp(tempChannelTable);
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
        end
        
        function displayReadDelaySortedChannelTable(obj)
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
            fprintf("<strong> Channels Sorted by Read Delay: </strong>\n")
            sortedChannelTable = obj.channelTable(:, 2:end);
            sortedChannelTable.Properties.VariableNames(1) = "instruments";
            sortedChannelTable.rampRates = cellfun(@(x) x.', sortedChannelTable.rampRates, UniformOutput = false);
            sortedChannelTable.rampThresholds = cellfun(@(x) x.', sortedChannelTable.rampThresholds, UniformOutput = false);
            sortedChannelTable.softwareMins = cellfun(@(x) x.', sortedChannelTable.softwareMins, UniformOutput = false);
            sortedChannelTable.softwareMaxs = cellfun(@(x) x.', sortedChannelTable.softwareMaxs, UniformOutput = false);
            if ~isempty(sortedChannelTable)
                sortedChannelTable = sortrows(sortedChannelTable, "readDelays", "descend");
            end
            disp(sortedChannelTable);
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
        end
        
        function flush(obj)
            % Flush communication buffer for all instruments in the rack
            for i = 1:height(obj.instrumentTable)
                instrument = obj.instrumentTable.instruments(i);
                instrument.flush();
            end
        end
               
    end
    
    methods (Access = private)

        function lockGuard = activateBatchGetLock(obj)
            assert(~obj.isBatchGetActive, "instrumentRack:ActiveBatchGet", ...
                "Cannot start a new batch get while another batch get is in progress.");
            % Important: if guard construction errors after setting the flag,
            % retries will see a stuck lock. Ensure we roll back on failure.
            obj.isBatchGetActive = true;
            try
                lockGuard = onCleanup(@() obj.clearBatchGetLock());
            catch ME
                obj.isBatchGetActive = false;
                rethrow(ME);
            end
        end

        function clearBatchGetLock(obj)
            obj.isBatchGetActive = false;
        end

        function flushInstrumentsSafe(obj, instruments, context)
            arguments
                obj %#ok<INUSA>
                instruments (:, 1) instrumentInterface
                context (1, 1) string {mustBeNonzeroLengthText} = ""
            end
            for i = 1:numel(instruments)
                instrument = instruments(i);
                if ~isvalid(instrument)
                    continue;
                end
                try
                    instrument.flush();
                catch ME
                    warning("instrumentRack:flushFailed", ...
                        "Failed to flush instrument (%s). Continuing. Error: %s", context, ME.message);
                end
            end
        end
        
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
                setTable.reachedTargets{i} = false(size(startValues));
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
                % avoid sending too many commands too quickly
                %if ~isempty(setTable)
                    pause(0.75); % avoid busy-waiting
                %end
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
        
        function limitedValues = enforceSoftwareLimits(~, values, minLimits, maxLimits)
            limitedValues = values;
            if isempty(limitedValues)
                return;
            end
            if isrow(limitedValues)
                limitedValues = limitedValues.';
            end
            if isrow(minLimits)
                minLimits = minLimits.';
            end
            if isrow(maxLimits)
                maxLimits = maxLimits.';
            end
            assert(numel(limitedValues) == numel(minLimits) && numel(limitedValues) == numel(maxLimits), ...
                "Software limits must match channel size.");
            limitedValues = min(max(limitedValues, minLimits), maxLimits);
        end
        
        function handleRetryError(obj, ME, locationName, tries)
            if tries >= obj.tryTimes
                obj.dispLine()
                obj.dispTime()
                fprintf("An error occured during %s\n", locationName);
                rethrow(ME);
            else
                obj.dispLine()
                obj.dispTime()
                fprintf("An error occured during %s\n", locationName);
                
                obj.dispPartialStackTrace(ME);
                
                obj.dispTime()
                obj.dispLine()
            end
        end
        
    end
    methods (Static, Access = private)
        
        function dispPartialStackTrace(ME)
            % Displays the error message and the first few stack frames with hyperlinks
            
            % Get full extended report with hyperlinks
            report = getReport(ME, "extended", "hyperlinks", "on");
            
            % Split into lines and convert to string array for easier handling
            reportLines = string(splitlines(report));
            
            % Identify entries (Error using ... / Error in ...)
            isEntryStart = startsWith(reportLines, "Error using ") | startsWith(reportLines, "Error in ");
            entryStartIndices = find(isEntryStart);
            
            % Keep first 3 entries
            if length(entryStartIndices) > 3
                cutoff = entryStartIndices(4);
                reportLines = reportLines(1:cutoff-1);
                % Add note about hidden trace
                reportLines(end+1) = "Partial stack trace shown. Further stack trace has been hidden.";
            end
            
            % Display
            disp(join(reportLines, newline));
        end
        
        function dispLine()
            disp(join(repelem("=", 120), ""));
        end
        
        function dispTime()
            fprintf(string(datetime("now")) + "\n");
        end
        
    end
    
    
end