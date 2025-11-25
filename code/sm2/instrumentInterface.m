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
    end

    properties (Access = private)
        lastGetChannelIndex;
        lastSetValues = {};
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
            channel = obj.channelTable.channels(channelIndex);
            getValues = obj.getChannel(channel);
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
    
    methods (Access = ?instrumentRack, Sealed)

        function getWriteChannel(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            obj.performGetWrite(channel);
        end

        function getValues = getReadChannel(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            getValues = obj.performGetRead(channel);
        end

    end

    methods (Sealed)

        function getValues = getChannel(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            obj.performGetWrite(channel);
            getValues = obj.performGetRead(channel);
        end

        function setChannel(obj, channel, setValues)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                setValues double {mustBeVector};
            end
            obj.setWriteChannel(channel, setValues);
            if ~obj.setCheckChannel(channel)
                startTime = datetime("now");
                while ~obj.setCheckChannel(channel) && (datetime("now") - startTime) < obj.setTimeout
                    if obj.setInterval > 0
                        pause(seconds(obj.setInterval));
                    end
                end
            end
        end

        function setWriteChannel(obj, channel, setValues)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
                setValues double {mustBeVector};
            end
            channelIndex = obj.findChannelIndex(channel);
            % check validity of setValues
            obj.checkSize(channelIndex, setValues);
            % LLM note: After checkSize and the arguments validation above,
            % helper overrides receive a column double whose length matches
            % the declared channel. Redundant scalar extractors (e.g. in
            % virtual instruments) are unnecessary.
            assert(all(~isnan(setValues)), "setWrite for channel %s received nan value(s). Received:\n%s", channel, formattedDisplayText(setValues));
            % enforce column vector
            if ~isscalar(setValues) && isrow(setValues)
                setValues = setValues.';
            end
            obj.setWriteChannelHelper(channelIndex, setValues);
            obj.lastSetValues{channelIndex} = setValues;

            % make sure that this cannot be between getWrite and getRead
            obj.lastGetChannelIndex = [];
        end

        function TF = setCheckChannel(obj, channel)
            % TF is a single logical
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            
            % If requireSetCheck is false, always return true
            if ~obj.requireSetCheck
                TF = true;
                return;
            end
            
            channelIndex = obj.findChannelIndex(channel);
            channelLastSetValues = obj.lastSetValues{channelIndex};
            assert(~isempty(channelLastSetValues), "setWriteChannel for channel %s has not been called succesfully yet.", channel);
            TF = obj.setCheckChannelHelper(channelIndex, channelLastSetValues);
        end

        function channelIndex = findChannelIndex(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            channelIndex = find(obj.channelTable.channels == channel);
            assert(~isempty(channelIndex), "%s is not found in the instrument.", channel);
        end

        function channelSize = findChannelSize(obj, channel)
            arguments
                obj;
                channel (1, 1) string {mustBeNonzeroLengthText};
            end
            channelSize = obj.channelTable.channelSizes(obj.findChannelIndex(channel));
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

        function performGetWrite(obj, channel)
            channelIndex = obj.findChannelIndex(channel);
            obj.getWriteChannelHelper(channelIndex);
            obj.lastGetChannelIndex = channelIndex;
        end

        function getValues = performGetRead(obj, channel)
            assert(~isempty(obj.lastGetChannelIndex), "getWrite has not been called for channel %s, or setWrite has been called", channel);
            channelIndex = obj.findChannelIndex(channel);
            assert(channelIndex == obj.lastGetChannelIndex, "Last getWrite was channel %s, but getRead was called for channel %s.", obj.channelTable.channels(obj.lastGetChannelIndex), channel);
            getValues = obj.getReadChannelHelper(channelIndex);
            obj.checkSize(channelIndex, getValues);
            if ~isscalar(getValues) && isrow(getValues)
                warning("Channel %s returned a row vector while getting. A column vector is preferred.", channel);
                getValues = getValues.';
            end
        end

        function checkSize(obj, channelIndex, values)
            channelSize = obj.channelTable.channelSizes(channelIndex);
            assert(length(values) == channelSize, "Expected channel %s to have length %d. Received length %d instead.", obj.channelTable.channels(channelIndex), channelSize, length(values));
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
            if ~isempty(obj.channelTable)
                assert(~any(channel == obj.channelTable.channels), "Channels must not repeat.");
            end
            obj.channelTable = [obj.channelTable; {channel, channelSize}];
            obj.lastSetValues = cell(height(obj.channelTable), 1);
            obj.setTolerances = [obj.setTolerances, {NameValueArgs.setTolerances}];
        end

    end

end