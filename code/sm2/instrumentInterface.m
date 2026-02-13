classdef (Abstract) instrumentInterface < handle & matlab.mixin.Heterogeneous
    % Thomas 20241221
    % an abstract interface for all instruments
    % only numeric values are allowed as channels. non-numeric values
    % should be made into class methods.
    %#ok<*INUSD>
    properties (SetAccess = protected)
        channelTable = table(Size = [0, 2], ...
            VariableTypes = ["string", "uint64"], ...
            VariableNames = ["channels", "channelSizes"]);
    end

    properties (SetAccess = protected)
        address string;
        communicationHandle;
        setTolerances = {};
    end

    properties
        setTimeout (1, 1) duration = minutes(1);
        setInterval (1, 1) duration = seconds(2);
        requireSetCheck (1, 1) logical = true;
        writeCommandInterval (1, 1) duration = seconds(0);
        writeCommandIntervalMinWrites (1, 1) double {mustBeNonnegative, mustBeInteger} = 3;
    end

    properties (SetAccess = protected)
        % Number of *additional* pool workers required by this instrument.
        % 0 means the instrument is self-contained in the calling process.
        numWorkersRequired (1, 1) double {mustBeNonnegative, mustBeInteger} = 0;
    end

    properties (Access = private)
        lastGetChannelIndex;
        lastSetValues = {};
        channelNameToIndex = dictionary(string.empty(0, 1), uint32.empty(0, 1));
        lastWriteCommandTic = [];
        writesSinceLastRead (1, 1) double {mustBeNonnegative, mustBeInteger} = 0;
    end

    methods (Abstract, Access = ?instrumentInterface)
        % MUST IMPLEMENT THESE METHODS:
        
        % getWriteChannelHelper: Send commands to instrument without reading response
        % This is called first to initiate measurements. Separating write/read 
        % allows instrumentRack to optimize batch operations by sending all
        % write commands first, then reading all responses in sequence.
        % This minimizes instrument settling time since all measurements can
        % start simultaneously.
        getWriteChannelHelper(obj, channelIndex);
        
        % getReadChannelHelper: Read response from instrument after getWrite
        % This is called after getWriteChannelHelper to retrieve the actual data.
        % Many instruments need time to physically average/settle after receiving
        % a query command, so separating these operations improves efficiency.
        getValues = getReadChannelHelper(obj, channelIndex);
    end

    methods (Access = ?instrumentInterface)
        % OPTIONAL OVERRIDE METHODS:
        
        % setWriteChannelHelper: Send set commands without verification
        % This is called first for all settable channels. Separating write/check
        % allows instrumentRack to send all set commands simultaneously, then
        % verify all values have been reached in batch. Critical for instruments
        % with slow settling times (voltage sources, etc.)
        function setWriteChannelHelper(obj, channelIndex, setValues)
            error("Set action unsupported for channel %s", obj.channelTable.channels(channelIndex));
        end

        % setCheckChannelHelper: Verify set values are within tolerance
        % Called after setWriteChannelHelper to confirm values have settled.
        % Only called for channels with setTolerances defined.
        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            % returns a single logical
            getValues = obj.getChannelByIndex(channelIndex);
            TF = all(abs(getValues - channelLastSetValues) <= obj.setTolerances{channelIndex});
        end
    end

    methods
        % destructor; override according to needs
        function delete(obj)
            %Gracefully closes connection to instrument. Many instruments
            %requires overriding this default implementation. This
            %implementation is redundant but serves as an example
            
            %delete(obj.communicationHandle);
        end
        
        function flush(~)
            % Default flush implementation - does nothing
            % Override in specific instruments if flushing is needed
        end
    end

    methods (Access = ?measurementEngine, Sealed)
        function validateWorkersRequestedFromRecipe(obj, numeWorkersRequested)
            arguments
                obj
                numeWorkersRequested (1, 1) double {mustBeNonnegative, mustBeInteger}
            end

            if double(obj.numWorkersRequired) ~= double(numeWorkersRequested)
                error("instrumentInterface:WorkersRequestedMismatch", ...
                    "%s declares numWorkersRequired=%d but recipe requested numeWorkersRequested=%d.", ...
                    class(obj), double(obj.numWorkersRequired), double(numeWorkersRequested));
            end
        end
    end
    
    methods (Access = {?instrumentRack, ?instrumentInterface}, Sealed)

        function channelSize = findChannelSizeByIndex(obj, channelIndex)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            channelSize = obj.channelTable.channelSizes(channelIndex);
        end

        function getWriteChannelByIndex(obj, channelIndex)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            obj.performGetWriteByIndex(channelIndex);
        end

        function getValues = getReadChannelByIndex(obj, channelIndex)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            getValues = obj.performGetReadByIndex(channelIndex);
        end

        function getValues = getChannelByIndex(obj, channelIndex)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            obj.performGetWriteByIndex(channelIndex);
            getValues = obj.performGetReadByIndex(channelIndex);
        end

        function setChannelByIndex(obj, channelIndex, setValues)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
                setValues double {mustBeVector};
            end
            obj.setWriteChannelByIndex(channelIndex, setValues);
            if ~obj.setCheckChannelByIndex(channelIndex)
                startTime = datetime("now");
                while ~obj.setCheckChannelByIndex(channelIndex) && (datetime("now") - startTime) < obj.setTimeout
                    if obj.setInterval > 0
                        pause(seconds(obj.setInterval));
                    end
                end
            end
        end

        function setWriteChannelByIndex(obj, channelIndex, setValues)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
                setValues double {mustBeVector};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            channel = obj.channelTable.channels(channelIndex);
            obj.checkSize(channelIndex, setValues);
            assert(all(~isnan(setValues)), "setWrite for channel %s received nan value(s). Received:\n%s", channel, formattedDisplayText(setValues));
            if ~isscalar(setValues) && isrow(setValues)
                setValues = setValues.';
            end
            obj.enforceWriteCommandInterval();
            obj.setWriteChannelHelper(channelIndex, setValues);
            obj.lastSetValues{channelIndex} = setValues;

            % make sure that this cannot be between getWrite and getRead
            obj.lastGetChannelIndex = [];
        end

        function TF = setCheckChannelByIndex(obj, channelIndex)
            arguments
                obj;
                channelIndex (1, 1) {mustBePositive, mustBeInteger};
            end
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            if ~obj.requireSetCheck
                TF = true;
                return;
            end
            obj.enforceWriteCommandInterval();
            channel = obj.channelTable.channels(channelIndex);
            channelLastSetValues = obj.lastSetValues{channelIndex};
            assert(~isempty(channelLastSetValues), "setWriteChannel for channel %s has not been called succesfully yet.", channel);
            TF = obj.setCheckChannelHelper(channelIndex, channelLastSetValues);
        end

    end

    methods (Sealed)

        function getValues = getChannel(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            channelIndex = obj.findChannelIndex(channel);
            getValues = obj.getChannelByIndex(channelIndex);
        end

        function setChannel(obj, channel, setValues)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                setValues double {mustBeVector};
            end
            channelIndex = obj.findChannelIndex(channel);
            obj.setChannelByIndex(channelIndex, setValues);
        end

        function setWriteChannel(obj, channel, setValues)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                setValues double {mustBeVector};
            end
            channelIndex = obj.findChannelIndex(channel);
            obj.setWriteChannelByIndex(channelIndex, setValues);
        end

        function TF = setCheckChannel(obj, channel)
            % TF is a single logical
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            channelIndex = obj.findChannelIndex(channel);
            TF = obj.setCheckChannelByIndex(channelIndex);
        end

        function channelIndex = findChannelIndex(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            assert(isKey(obj.channelNameToIndex, channel), "%s is not found in the instrument.", channel);
            channelIndex = double(obj.channelNameToIndex(channel));
        end

        function channelSize = findChannelSize(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            channelIndex = obj.findChannelIndex(channel);
            channelSize = obj.findChannelSizeByIndex(channelIndex);
        end

        function setSetTolerances(obj, channel, newSetTolerances)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                newSetTolerances double {mustBePositive, mustBeVector, mustBeNonempty};
            end
            channelIndex = obj.findChannelIndex(channel);
            obj.checkSize(channelIndex, newSetTolerances);
            if ~isscalar(newSetTolerances) && isrow(newSetTolerances)
                newSetTolerances = newSetTolerances.';
            end
            obj.setTolerances{channelIndex} = newSetTolerances;
        end

        % seals common functions so arrays can be arguments
        function TF = ne(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = ne(obj1.address, obj2.address); 
            end
        end

        function TF = eq(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = eq(obj1.address, obj2.address);
            end
        end

        function TF = gt(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = gt(obj1.address, obj2.address);
            end
        end

        function TF = ge(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = ge(obj1.address, obj2.address);
            end
        end

        function TF = lt(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = lt(obj1.address, obj2.address);
            end
        end

        function TF = le(objs1, objs2)
            TF = false(size(objs1));
            for objIndex = 1:numel(objs1)
                obj1 = objs1(objIndex);
                obj2 = objs2(objIndex);
                TF(objIndex) = le(obj1.address, obj2.address);
            end
        end

    end

    methods (Access = private, Sealed)

        function performGetWriteByIndex(obj, channelIndex)
            obj.enforceWriteCommandInterval();
            obj.getWriteChannelHelper(channelIndex);
            obj.lastGetChannelIndex = channelIndex;
        end

        function getValues = performGetReadByIndex(obj, channelIndex)
            channelIndex = obj.normalizeChannelIndex(channelIndex);
            channel = obj.channelTable.channels(channelIndex);
            assert(~isempty(obj.lastGetChannelIndex), "getWrite has not been called for channel %s, or setWrite has been called", channel);
            assert(channelIndex == obj.lastGetChannelIndex, "Last getWrite was channel %s, but getRead was called for channel %s.", obj.channelTable.channels(obj.lastGetChannelIndex), channel);
            getValues = obj.getReadChannelHelper(channelIndex);
            obj.checkSize(channelIndex, getValues);
            if ~isscalar(getValues) && isrow(getValues)
                warning("Channel %s returned a row vector while getting. A column vector is preferred.", channel);
                getValues = getValues.';
            end
            obj.lastWriteCommandTic = [];
            obj.writesSinceLastRead = 0;
        end

        function channelIndex = normalizeChannelIndex(obj, channelIndex)
            channelIndex = double(channelIndex);
            assert(channelIndex >= 1 && channelIndex <= height(obj.channelTable), ...
                "Channel index %d is out of range.", channelIndex);
        end

        function checkSize(obj, channelIndex, values)
            channelSize = obj.channelTable.channelSizes(channelIndex);
            assert(length(values) == channelSize, "Expected channel %s to have length %d. Received length %d instead.", obj.channelTable.channels(channelIndex), channelSize, length(values));
        end

        function enforceWriteCommandInterval(obj)
            intervalSeconds = seconds(obj.writeCommandInterval);
            assert(intervalSeconds >= 0, "writeCommandInterval must be nonnegative.");
            minWrites = obj.writeCommandIntervalMinWrites;
            if intervalSeconds > 0 && obj.writesSinceLastRead >= minWrites && ~isempty(obj.lastWriteCommandTic)
                remaining = intervalSeconds - toc(obj.lastWriteCommandTic);
                if remaining > 0
                    pause(remaining);
                end
            end
            obj.lastWriteCommandTic = tic;
            obj.writesSinceLastRead = obj.writesSinceLastRead + 1;
        end

    end

    methods (Access = protected, Sealed)
        function addChannel(obj, channel, channelSize, NameValueArgs)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                channelSize (1, 1) uint64 {mustBePositive, mustBeInteger} = 1;
                NameValueArgs.setTolerances (:, 1) double {mustBePositive} = 1E-6 * ones(channelSize, 1);
            end
            assert(length(NameValueArgs.setTolerances) == channelSize, "setTolerances must be a channelSize long column vector.")
            assert(~isKey(obj.channelNameToIndex, channel), "Channels must not repeat.");
            obj.channelTable = [obj.channelTable; {channel, channelSize}];
            obj.channelNameToIndex(channel) = uint32(height(obj.channelTable));
            obj.lastSetValues = cell(height(obj.channelTable), 1);
            obj.setTolerances = [obj.setTolerances, {NameValueArgs.setTolerances}];
        end

    end

end