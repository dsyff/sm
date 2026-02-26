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
        channelTable = table(Size = [0, 12], ...
            VariableTypes = ["instrumentInterface", "string", "string", "string", "uint32", "uint64", "double", "cell", "cell", "cell", "cell", "logical"], ...
            VariableNames = ["instruments", "instrumentFriendlyNames", "channels", "channelFriendlyNames", "channelIndices", "channelSizes", "readDelays", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs", "virtual"]);
    end
    properties (Access = private)
        isBatchGetActive logical = false;
        channelFriendlyNameToRowIndex = dictionary(string.empty(0, 1), uint32.empty(0, 1));
        rackGetPlanCache = dictionary(string.empty(0, 1), cell.empty(0, 1));
        channelReadDelaySortOrder (:, 1) uint32 = uint32.empty(0, 1);
        channelReadDelayRanks (:, 1) uint32 = uint32.empty(0, 1);
        lastSetValues (:, 1) cell = cell(0, 1);
        lastCheckedValues (:, 1) cell = cell(0, 1);
    end
    methods
        function obj = instrumentRack(skipDialog)
            arguments
                skipDialog logical = false;
            end
            assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");
            assert(exist("dictionary", "class") == 8, "instrumentRack requires dictionary support.");
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
                            experimentContext.print("instrumentRack delete warning: failed to delete instrument %s: %s", friendlyName, ME.message);
                        end
                    end
                end
            end
            obj.instrumentTable = obj.instrumentTable([], :);
            obj.channelTable = obj.channelTable([], :);
            obj.channelFriendlyNameToRowIndex = dictionary(string.empty(0, 1), uint32.empty(0, 1));
            obj.rackGetPlanCache = dictionary(string.empty(0, 1), cell.empty(0, 1));
            obj.channelReadDelaySortOrder = uint32.empty(0, 1);
            obj.channelReadDelayRanks = uint32.empty(0, 1);
            obj.lastSetValues = cell(0, 1);
            obj.lastCheckedValues = cell(0, 1);
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
            
            % resolve and cache instrument-local channel index once
            channelIndex = instrument.findChannelIndex(channel);
            channelSize = instrument.findChannelSizeByIndex(channelIndex);
            
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
                    instrument.getChannelByIndex(channelIndex);
                    
                    % obtain response time of getRead over a few trials
                    readDelayArray = nan(5, 1);
                    trials = 5;
                    for tryIndex = 1:trials
                        instrument.getWriteChannelByIndex(channelIndex);
                        startTime = tic;
                        instrument.getReadChannelByIndex(channelIndex);
                        readDelayArray(tryIndex) = toc(startTime);
                    end
                    readDelay = median(readDelayArray);
                catch ME
                    obj.dispLine()
                    obj.dispTime()
                    experimentContext.print("Failed to read %s/%s.", instrumentFriendlyName, channel);
                    obj.dispPartialStackTrace(ME);
                    obj.dispTime()
                    obj.dispLine()
                    readDelay = inf;
                end
            end
            
            newTable = [obj.channelTable; {instrument, instrumentFriendlyName, channel, channelFriendlyName, uint32(channelIndex), channelSize, readDelay, {rampRates}, {rampThresholds}, {softwareMins}, {softwareMaxs}, instrumentVirtualFlag}];
            
            % check for repetitions
            if ~isempty(obj.channelTable)
                assert(~matches(channelFriendlyName, obj.channelTable.channelFriendlyNames), "Channel friendly name must not repeat.");
                duplicateMask = obj.channelTable.instrumentFriendlyNames == instrumentFriendlyName ...
                    & obj.channelTable.channels == channel;
                assert(~any(duplicateMask), "Channels must not repeat.");
            end
            obj.channelTable = newTable;
            obj.channelFriendlyNameToRowIndex(channelFriendlyName) = uint32(height(obj.channelTable));
            [~, sortOrder] = sort(obj.channelTable.readDelays, "descend");
            obj.channelReadDelaySortOrder = uint32(sortOrder);
            obj.channelReadDelayRanks = zeros(height(obj.channelTable), 1, "uint32");
            obj.channelReadDelayRanks(sortOrder) = uint32(1:height(obj.channelTable));
            obj.rackGetPlanCache = dictionary(string.empty(0, 1), cell.empty(0, 1));
            rowIndex = height(obj.channelTable);
            obj.lastSetValues{rowIndex, 1} = [];
            obj.lastCheckedValues{rowIndex, 1} = [];
        end

        function info = getRackInfoForEditing(obj)
            info = obj.channelTable(:, ["instrumentFriendlyNames", "channelFriendlyNames", "channelSizes", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"]);
            info.Properties.VariableNames = ["instrumentFriendlyName", "channelFriendlyName", "channelSize", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"];
            info.channelSize = double(info.channelSize(:));
            info.rampRates = cellfun(@(x) double(x(:).'), info.rampRates, UniformOutput = false);
            info.rampThresholds = cellfun(@(x) double(x(:).'), info.rampThresholds, UniformOutput = false);
            info.softwareMins = cellfun(@(x) double(x(:).'), info.softwareMins, UniformOutput = false);
            info.softwareMaxs = cellfun(@(x) double(x(:).'), info.softwareMaxs, UniformOutput = false);
        end

        function applyRackEditPatch(obj, patch)
            arguments
                obj
                patch (1, 1) instrumentRackEditPatch
            end

            if patch.isEmpty()
                return;
            end

            entries = patch.entries;
            channelNames = entries.channelFriendlyName(:);
            channelRowIndices = obj.findChannelIndices(channelNames);
            numRows = numel(channelRowIndices);

            rampRates = cell(numRows, 1);
            rampThresholds = cell(numRows, 1);
            softwareMins = cell(numRows, 1);
            softwareMaxs = cell(numRows, 1);
            for i = 1:numRows
                channelName = channelNames(i);
                channelSize = double(obj.channelTable.channelSizes(channelRowIndices(i)));
                rampRates{i} = normalizeValues(entries.rampRates{i}, channelSize, channelName, "rampRates", true);
                rampThresholds{i} = normalizeValues(entries.rampThresholds{i}, channelSize, channelName, "rampThresholds", true);
                softwareMins{i} = normalizeValues(entries.softwareMins{i}, channelSize, channelName, "softwareMins", false);
                softwareMaxs{i} = normalizeValues(entries.softwareMaxs{i}, channelSize, channelName, "softwareMaxs", false);
                if any(softwareMins{i} >= softwareMaxs{i})
                    error("instrumentRack:InvalidSoftwareLimits", ...
                        "Channel %s requires softwareMins < softwareMaxs elementwise.", channelName);
                end
            end

            for i = 1:numRows
                rowIndex = channelRowIndices(i);
                obj.channelTable.rampRates{rowIndex} = rampRates{i};
                obj.channelTable.rampThresholds{rowIndex} = rampThresholds{i};
                obj.channelTable.softwareMins{rowIndex} = softwareMins{i};
                obj.channelTable.softwareMaxs{rowIndex} = softwareMaxs{i};
            end

            function valuesOut = normalizeValues(valuesIn, expectedSize, channelName, fieldName, positiveOnly)
                if ~(isnumeric(valuesIn) && isvector(valuesIn) && isreal(valuesIn))
                    error("instrumentRack:InvalidRackEditPatch", ...
                        "Channel %s %s must be a real numeric vector.", channelName, fieldName);
                end
                valuesOut = double(valuesIn(:));
                if isempty(valuesOut)
                    error("instrumentRack:InvalidRackEditPatch", ...
                        "Channel %s %s cannot be empty.", channelName, fieldName);
                end
                if isscalar(valuesOut)
                    valuesOut = repmat(valuesOut, expectedSize, 1);
                elseif numel(valuesOut) ~= expectedSize
                    error("instrumentRack:InvalidRackEditPatch", ...
                        "Channel %s %s must be scalar or length %d.", channelName, fieldName, expectedSize);
                end
                if any(isnan(valuesOut))
                    error("instrumentRack:InvalidRackEditPatch", ...
                        "Channel %s %s cannot contain NaN.", channelName, fieldName);
                end
                if positiveOnly && any(valuesOut <= 0)
                    error("instrumentRack:InvalidRackEditPatch", ...
                        "Channel %s %s must be strictly positive.", channelName, fieldName);
                end
            end
        end
        
        function values = rackGet(obj, channelFriendlyNames)
            arguments
                obj;
                channelFriendlyNames string {mustBeNonzeroLengthText, mustBeVector};
            end
            
            channelFriendlyNames = channelFriendlyNames(:);
            cacheKey = strjoin(channelFriendlyNames, string(char(31)));
            if isKey(obj.rackGetPlanCache, cacheKey)
                planCell = obj.rackGetPlanCache(cacheKey);
                plan = planCell{1};
            else
                channelRowIndices = obj.findChannelIndices(channelFriendlyNames);
                instruments = obj.channelTable.instruments(channelRowIndices);
                channelIndices = obj.channelTable.channelIndices(channelRowIndices);
                instrumentFriendlyNames = obj.channelTable.instrumentFriendlyNames(channelRowIndices);
                virtualMask = obj.channelTable.virtual(channelRowIndices);
                virtualPositions = find(virtualMask);
                physicalPositions = find(~virtualMask);

                physicalBatches = cell(0, 1);
                if ~isempty(physicalPositions)
                    [~, physicalOrder] = sort(obj.channelReadDelayRanks(channelRowIndices(physicalPositions)), "ascend");
                    remaining = physicalPositions(physicalOrder);
                    while ~isempty(remaining)
                        seenInstrumentNames = dictionary(string.empty(0, 1), logical.empty(0, 1));
                        takeMask = false(size(remaining));
                        for remainingIndex = 1:numel(remaining)
                            requestIndex = remaining(remainingIndex);
                            instrumentName = instrumentFriendlyNames(requestIndex);
                            if ~isKey(seenInstrumentNames, instrumentName)
                                seenInstrumentNames(instrumentName) = true;
                                takeMask(remainingIndex) = true;
                            end
                        end
                        physicalBatches{end + 1, 1} = uint32(remaining(takeMask)); %#ok<AGROW>
                        remaining = remaining(~takeMask);
                    end
                end

                plan = struct( ...
                    "instruments", instruments, ...
                    "channelIndices", channelIndices, ...
                    "virtualPositions", uint32(virtualPositions), ...
                    "physicalBatches", {physicalBatches}, ...
                    "numChannels", uint32(numel(channelRowIndices)));
                obj.rackGetPlanCache(cacheKey) = {plan};
            end
            
            assert(~obj.isBatchGetActive, "instrumentRack:ActiveBatchGet", ...
                "Cannot call rackGet while a batch get is already in progress.");

            tries = 0;
            while tries < obj.tryTimes
                try
                    getValues = cell(double(plan.numChannels), 1);

                    if ~isempty(plan.physicalBatches)
                        lockGuard = obj.activateBatchGetLock(); %#ok<NASGU>
                        timeoutSeconds = seconds(obj.batchGetTimeout);
                        startTimer = tic;
                        for batchListIndex = 1:numel(plan.physicalBatches)
                            assert(toc(startTimer) < timeoutSeconds, "Timed out while performing batch get.");
                            batchRequestIndices = double(plan.physicalBatches{batchListIndex});
                            pendingInstruments = plan.instruments(batchRequestIndices);
                            pendingCount = 0;
                            try
                                for batchIndex = 1:numel(batchRequestIndices)
                                    requestIndex = batchRequestIndices(batchIndex);
                                    instrument = plan.instruments(requestIndex);
                                    channelIndex = plan.channelIndices(requestIndex);
                                    instrument.getWriteChannelByIndex(channelIndex);
                                    pendingCount = batchIndex;
                                end
                                for batchIndex = numel(batchRequestIndices):-1:1
                                    requestIndex = batchRequestIndices(batchIndex);
                                    instrument = plan.instruments(requestIndex);
                                    channelIndex = plan.channelIndices(requestIndex);
                                    getValues{requestIndex} = instrument.getReadChannelByIndex(channelIndex);
                                    % Reads occur in reverse order of writes, so pending is a stack.
                                    if pendingCount > 0
                                        pendingCount = pendingCount - 1;
                                    end
                                end
                            catch MEBatch
                                if pendingCount > 0
                                    obj.flushInstrumentsSafe(pendingInstruments(1:pendingCount), "rackGet batch cleanup before retry");
                                end
                                rethrow(MEBatch);
                            end
                        end
                        clear lockGuard;
                    end

                    if ~isempty(plan.virtualPositions)
                        for virtualIndex = double(plan.virtualPositions(:)).'
                            instrument = plan.instruments(virtualIndex);
                            channelIndex = plan.channelIndices(virtualIndex);
                            getValues{virtualIndex} = instrument.getChannelByIndex(channelIndex);
                        end
                    end

                    % Concatenate all values in order
                    values = vertcat(getValues{:});
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
            
            channelRowIndices = obj.findChannelIndices(channelFriendlyNames);
            setValues = obj.buildSetValuesForRows(channelRowIndices, values);
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    obj.rackSetWriteHelper(channelRowIndices, setValues);
                    obj.cacheLastSetValues(channelRowIndices, setValues);
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
            
            channelRowIndices = obj.findChannelIndices(channelFriendlyNames);
            setValues = obj.buildSetValuesForRows(channelRowIndices, values);
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    obj.rackSetWriteHelper(channelRowIndices, setValues);
                    obj.cacheLastSetValues(channelRowIndices, setValues);
                    
                    timeoutSeconds = seconds(obj.batchSetTimeout);
                    startTimer = tic;
                    pendingRowIndices = channelRowIndices;
                    TFs = obj.rackVectorSetCheckHelper(pendingRowIndices);
                    obj.promoteLastSetValues(pendingRowIndices, TFs);
                    while ~all(TFs)
                        assert(toc(startTimer) < timeoutSeconds, "Timed out while performing batch set.");
                        pendingRowIndices = pendingRowIndices(~TFs);
                        TFs = obj.rackVectorSetCheckHelper(pendingRowIndices);
                        obj.promoteLastSetValues(pendingRowIndices, TFs);
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
            
            channelRowIndices = obj.findChannelIndices(channelFriendlyNames);
            
            tries = 0;
            while tries < obj.tryTimes
                try
                    TF = obj.rackSetCheckHelper(channelRowIndices);
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
            experimentContext.print(obj.formattedDisplayText());
        end

        function txt = formattedDisplayText(obj)
            divider = join(repelem("=", 120), "");

            propertyNames = string({metaclass(obj).PropertyList.Name});
            setAccess = string({metaclass(obj).PropertyList.SetAccess});
            propertyNames = propertyNames(setAccess == "public");

            settingsLines = strings(numel(propertyNames), 1);
            for idx = 1:numel(propertyNames)
                propertyName = propertyNames(idx);
                settingsLines(idx) = propertyName + " = " + string(obj.(propertyName));
            end

            tempInstrumentTable = obj.instrumentTable(:, 2:end);
            tempInstrumentTable.Properties.VariableNames(1) = "instruments";
            instrumentLines = splitlines(string(formattedDisplayText(tempInstrumentTable)));
            if numel(instrumentLines) > 1 && strlength(instrumentLines(end)) == 0
                instrumentLines = instrumentLines(1:end-1);
            end

            tempChannelTable = obj.channelTable(:, 2:end);
            tempChannelTable.Properties.VariableNames(1) = "instruments";
            hiddenVars = intersect(["channelIndices", "virtual"], string(tempChannelTable.Properties.VariableNames));
            if ~isempty(hiddenVars)
                tempChannelTable = removevars(tempChannelTable, hiddenVars);
            end
            tempChannelTable.rampRates = cellfun(@(x) x.', tempChannelTable.rampRates, UniformOutput = false);
            tempChannelTable.rampThresholds = cellfun(@(x) x.', tempChannelTable.rampThresholds, UniformOutput = false);
            tempChannelTable.softwareMins = cellfun(@(x) x.', tempChannelTable.softwareMins, UniformOutput = false);
            tempChannelTable.softwareMaxs = cellfun(@(x) x.', tempChannelTable.softwareMaxs, UniformOutput = false);
            channelLines = splitlines(string(formattedDisplayText(tempChannelTable)));
            if numel(channelLines) > 1 && strlength(channelLines(end)) == 0
                channelLines = channelLines(1:end-1);
            end

            lines = [ ...
                divider
                string(datetime("now"))
                divider
                " Settings: "
                settingsLines
                divider
                instrumentLines
                divider
                channelLines
                divider
                string(datetime("now"))
                divider];
            txt = strjoin(lines, newline);
        end
        
        function displayReadDelaySortedChannelTable(obj)
            obj.dispLine();
            obj.dispTime();
            obj.dispLine();
            experimentContext.print("<strong> Channels Sorted by Read Delay: </strong>");
            sortedChannelTable = obj.channelTable(:, 2:end);
            sortedChannelTable.Properties.VariableNames(1) = "instruments";
            hiddenVars = intersect(["channelIndices", "virtual"], string(sortedChannelTable.Properties.VariableNames));
            if ~isempty(hiddenVars)
                sortedChannelTable = removevars(sortedChannelTable, hiddenVars);
            end
            sortedChannelTable.rampRates = cellfun(@(x) x.', sortedChannelTable.rampRates, UniformOutput = false);
            sortedChannelTable.rampThresholds = cellfun(@(x) x.', sortedChannelTable.rampThresholds, UniformOutput = false);
            sortedChannelTable.softwareMins = cellfun(@(x) x.', sortedChannelTable.softwareMins, UniformOutput = false);
            sortedChannelTable.softwareMaxs = cellfun(@(x) x.', sortedChannelTable.softwareMaxs, UniformOutput = false);
            if ~isempty(sortedChannelTable)
                sortedChannelTable = sortedChannelTable(double(obj.channelReadDelaySortOrder), :);
            end
            experimentContext.print(sortedChannelTable);
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

        function flushInstrumentsSafe(~, instruments, context)
            arguments
                ~
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
            channelFriendlyNames = channelFriendlyNames(:);
            foundMask = isKey(obj.channelFriendlyNameToRowIndex, channelFriendlyNames);
            if ~all(foundMask)
                missingNames = strjoin(channelFriendlyNames(~foundMask), ", ");
                error("%s is not found in the rack.", missingNames);
            end
            channelIndices = double(obj.channelFriendlyNameToRowIndex(channelFriendlyNames));
        end
        
        function rackSetWriteHelperNoRamp(obj, channelRowIndices, setValues)
            instruments = obj.channelTable.instruments(channelRowIndices);
            channelIndices = obj.channelTable.channelIndices(channelRowIndices);
            for batchIndex = 1:numel(channelRowIndices)
                instrument = instruments(batchIndex);
                channelIndex = channelIndices(batchIndex);
                setValuesLocal = setValues{batchIndex};
                instrument.setWriteChannelByIndex(channelIndex, setValuesLocal);
            end
        end

        function setValues = buildSetValuesForRows(obj, channelRowIndices, values)
            channelSizes = obj.channelTable.channelSizes(channelRowIndices);
            expectedLength = sum(channelSizes);
            assert(expectedLength == length(values), "Expected length %d, got length %d in the set values instead.", expectedLength, length(values));
            setValues = cell(numel(channelRowIndices), 1);
            softwareMins = obj.channelTable.softwareMins(channelRowIndices);
            softwareMaxs = obj.channelTable.softwareMaxs(channelRowIndices);
            startIndex = 1;
            for i = 1:numel(channelRowIndices)
                channelSize = channelSizes(i);
                rawValues = values(startIndex : (startIndex + channelSize - 1));
                setValues{i} = obj.enforceSoftwareLimits(rawValues, softwareMins{i}, softwareMaxs{i});
                startIndex = startIndex + channelSize;
            end
        end

        function rackSetWriteHelper(obj, channelRowIndices, setValues)
            numRows = numel(channelRowIndices);
            rampRates = obj.channelTable.rampRates(channelRowIndices);
            rampThresholds = obj.channelTable.rampThresholds(channelRowIndices);

            isInstant = false(numRows, 1);
            for i = 1:numRows
                if all(isinf(rampRates{i}))
                    isInstant(i) = true;
                end
            end
            if any(isInstant)
                obj.rackSetWriteHelperNoRamp(channelRowIndices(isInstant), setValues(isInstant));
            end

            activeMask = ~isInstant;
            if ~any(activeMask)
                return;
            end

            activeRowIndices = channelRowIndices(activeMask);
            activeSetValues = setValues(activeMask);
            activeRampRates = rampRates(activeMask);
            activeRampThresholds = rampThresholds(activeMask);
            activeInstruments = obj.channelTable.instruments(activeRowIndices);
            activeChannelIndices = obj.channelTable.channelIndices(activeRowIndices);

            startValues = cell(numel(activeRowIndices), 1);
            reachedTargets = cell(numel(activeRowIndices), 1);
            isBelowThreshold = false(numel(activeRowIndices), 1);
            for i = 1:numel(activeRowIndices)
                cachedCheckedValues = obj.lastCheckedValues{activeRowIndices(i)};
                if isempty(cachedCheckedValues)
                    if all(isinf(activeRampThresholds{i}))
                        isBelowThreshold(i) = true;
                        startValues{i} = activeSetValues{i};
                        reachedTargets{i} = true(size(activeSetValues{i}));
                        continue;
                    end
                    startValues{i} = activeInstruments(i).getChannelByIndex(activeChannelIndices(i));
                else
                    startValues{i} = cachedCheckedValues;
                end
                deltas = abs(activeSetValues{i} - startValues{i});
                reachedTargets{i} = false(size(startValues{i}));
                if all(deltas < activeRampThresholds{i})
                    isBelowThreshold(i) = true;
                end
            end
            if any(isBelowThreshold)
                obj.rackSetWriteHelperNoRamp(activeRowIndices(isBelowThreshold), activeSetValues(isBelowThreshold));
            end

            activeKeepMask = ~isBelowThreshold;
            if ~any(activeKeepMask)
                return;
            end

            activeRowIndices = activeRowIndices(activeKeepMask);
            activeSetValues = activeSetValues(activeKeepMask);
            activeRampRates = activeRampRates(activeKeepMask);
            activeRampThresholds = activeRampThresholds(activeKeepMask);
            startValues = startValues(activeKeepMask);
            reachedTargets = reachedTargets(activeKeepMask);

            startTimer = tic;
            while ~isempty(activeRowIndices)
                totalElapsed = toc(startTimer);
                rampStepSetValues = activeSetValues;
                allReached = false(numel(activeRowIndices), 1);
                for i = 1:numel(activeRowIndices)
                    startValuesLocal = startValues{i};
                    setValuesLocal = activeSetValues{i};
                    rampRatesLocal = activeRampRates{i};
                    rampThresholdsLocal = activeRampThresholds{i};
                    reachedTargetsLocal = reachedTargets{i};
                    deltas = setValuesLocal - startValuesLocal;
                    signs = sign(deltas);
                    needRamp = ~reachedTargetsLocal;
                    if totalElapsed == 0
                        rampDistance = rampThresholdsLocal;
                    else
                        rampDistance = rampRatesLocal * totalElapsed;
                    end
                    rampStepSetValues{i} = setValuesLocal;
                    if any(needRamp)
                        rampStepSetValues{i}(needRamp) = startValuesLocal(needRamp) + signs(needRamp) .* rampDistance(needRamp);
                    end
                    overshoot = needRamp & (rampDistance >= abs(deltas));
                    if any(overshoot)
                        rampStepSetValues{i}(overshoot) = setValuesLocal(overshoot);
                    end
                    reachedTargetsLocal(overshoot) = true;
                    reachedTargets{i} = reachedTargetsLocal;
                    if all(reachedTargetsLocal)
                        allReached(i) = true;
                    end
                end

                obj.rackSetWriteHelperNoRamp(activeRowIndices, rampStepSetValues);
                keepMask = ~allReached;
                activeRowIndices = activeRowIndices(keepMask);
                activeSetValues = activeSetValues(keepMask);
                activeRampRates = activeRampRates(keepMask);
                activeRampThresholds = activeRampThresholds(keepMask);
                startValues = startValues(keepMask);
                reachedTargets = reachedTargets(keepMask);
            end
        end

        function TFs = rackVectorSetCheckHelper(obj, channelRowIndices)
            % returns logical column vector of the same length as channelRowIndices
            instruments = obj.channelTable.instruments(channelRowIndices);
            channelIndices = obj.channelTable.channelIndices(channelRowIndices);
            TFs = false(numel(channelRowIndices), 1);
            for batchIndex = 1:numel(channelRowIndices)
                TF = instruments(batchIndex).setCheckChannelByIndex(channelIndices(batchIndex));
                assert(isscalar(TF), "setCheckChannelByIndex should return a scalar logical, received length %d instead", length(TF));
                TFs(batchIndex) = TF;
            end
        end

        function TF = rackSetCheckHelper(obj, channelRowIndices)
            % returns a scalar logical indicating if all channels have reached their target
            instruments = obj.channelTable.instruments(channelRowIndices);
            channelIndices = obj.channelTable.channelIndices(channelRowIndices);
            for batchIndex = 1:numel(channelRowIndices)
                TF = instruments(batchIndex).setCheckChannelByIndex(channelIndices(batchIndex));
                assert(isscalar(TF), "setCheckChannelByIndex should return a scalar logical, received length %d instead", length(TF));
                if TF
                    obj.promoteLastSetValues(channelRowIndices(batchIndex), true);
                end
                if ~TF
                    return;
                end
            end
            TF = true;
        end

        function cacheLastSetValues(obj, channelRowIndices, setValues)
            for i = 1:numel(channelRowIndices)
                obj.lastSetValues{channelRowIndices(i)} = setValues{i};
            end
        end

        function promoteLastSetValues(obj, channelRowIndices, TFs)
            if isempty(channelRowIndices)
                return;
            end
            for i = 1:numel(channelRowIndices)
                if TFs(i)
                    rowIndex = channelRowIndices(i);
                    obj.lastCheckedValues{rowIndex} = obj.lastSetValues{rowIndex};
                end
            end
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
                experimentContext.print("An error occured during %s", locationName);
                rethrow(ME);
            else
                obj.dispLine()
                obj.dispTime()
                experimentContext.print("An error occured during %s", locationName);
                
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
            experimentContext.print(join(reportLines, newline));
        end
        
        function dispLine()
            experimentContext.print(join(repelem("=", 120), ""));
        end
        
        function dispTime()
            experimentContext.print(datetime("now"));
        end
        
    end
    
    
end
