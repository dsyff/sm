classdef instrumentWorkerRuntime < handle
    properties (SetAccess = private)
        instToInstWorkerQueue
        instWorkerToInstQueue
    end

    properties (Access = private)
        requestedBy string
        stringCommandNameToIndex
        channelNameToIndex
        actionNameToIndex
    end

    methods
        function obj = instrumentWorkerRuntime(instWorkerToInstQueue, requestedBy, stringCommands, channels)
            arguments
                instWorkerToInstQueue (1, 1) parallel.pool.PollableDataQueue
                requestedBy {mustBeTextScalar}
                stringCommands = string.empty(0, 1)
                channels = string.empty(0, 1)
            end

            obj.requestedBy = string(requestedBy);
            obj.instWorkerToInstQueue = instWorkerToInstQueue;
            obj.instToInstWorkerQueue = parallel.pool.PollableDataQueue;
            obj.stringCommandNameToIndex = dictionary(string.empty(0, 1), uint32.empty(0, 1));
            obj.channelNameToIndex = dictionary(string.empty(0, 1), uint32.empty(0, 1));
            actionNames = ["GET"; "SET"; "CHECK"];
            obj.actionNameToIndex = dictionary(actionNames, uint32((1:numel(actionNames)).'));

            if ~isempty(stringCommands)
                obj.instWorkerRegisterStringCommands(stringCommands);
            end
            if ~isempty(channels)
                obj.instWorkerRegisterChannels(channels);
            end

            send(obj.instWorkerToInstQueue, obj.instToInstWorkerQueue);
        end

        function indices = instWorkerRegisterStringCommands(obj, names)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                names
            end

            [obj.stringCommandNameToIndex, normalizedNames] = obj.buildNameIndexDictionary_(names, "string command");
            indices = obj.stringCommandNameToIndex(normalizedNames);
        end

        function indices = instWorkerRegisterChannels(obj, names)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                names
            end

            [obj.channelNameToIndex, normalizedNames] = obj.buildNameIndexDictionary_(names, "channel");
            indices = obj.channelNameToIndex(normalizedNames);
        end

        function instWorkerSendToInst(obj, payload)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                payload
            end

            send(obj.instWorkerToInstQueue, payload);
        end

        function command = instWorkerPollFromInst(obj, timeout)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                timeout duration = seconds(inf)
            end

            startTime = datetime("now");
            timeoutSeconds = seconds(timeout);
            while obj.instToInstWorkerQueue.QueueLength == 0
                if isfinite(timeoutSeconds)
                    assert(datetime("now") - startTime < timeout, ...
                        "instrumentWorkerRuntime:Timeout", ...
                        "Instrument worker %s did not receive a command in time.", obj.requestedBy);
                end
                pause(1E-6);
            end

            command = obj.normalizeCommand_(poll(obj.instToInstWorkerQueue));
        end

        function tf = instWorkerHasPendingFromInst(obj)
            arguments
                obj (1, 1) instrumentWorkerRuntime
            end

            tf = obj.instToInstWorkerQueue.QueueLength > 0;
        end

        function instWorkerSendExceptionToInst(obj, ME)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                ME (1, 1) MException
            end

            send(obj.instWorkerToInstQueue, ME);
        end

        function idx = instWorkerStringCommandIndex(obj, name)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                name {mustBeTextScalar}
            end

            idx = obj.lookupIndex_(obj.stringCommandNameToIndex, string(name), "string command");
        end

        function idx = instWorkerChannelIndex(obj, name)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                name {mustBeTextScalar}
            end

            idx = obj.lookupIndex_(obj.channelNameToIndex, string(name), "channel");
        end

        function idx = instWorkerActionIndex(obj, name)
            arguments
                obj (1, 1) instrumentWorkerRuntime
                name {mustBeTextScalar}
            end

            idx = obj.lookupIndex_(obj.actionNameToIndex, string(name), "action");
        end
    end

    methods (Access = private)
        function command = normalizeCommand_(obj, rawCommand)
            if isstruct(rawCommand)
                if ~(isfield(rawCommand, "channel") && isfield(rawCommand, "action"))
                    error("instrumentWorkerRuntime:InvalidCommand", ...
                        "Structured worker command must include channel and action fields.");
                end
                channelName = obj.normalizeTextScalar_(rawCommand.channel, "channel");
                actionName = obj.normalizeTextScalar_(rawCommand.action, "action");
                channelIndex = obj.instWorkerChannelIndex(channelName);
                actionIndex = obj.instWorkerActionIndex(actionName);

                value = [];
                if actionName == "SET"
                    if ~isfield(rawCommand, "value")
                        error("instrumentWorkerRuntime:InvalidCommand", ...
                            "SET worker command must include a value field.");
                    end
                    if isempty(rawCommand.value)
                        error("instrumentWorkerRuntime:InvalidCommand", ...
                            "SET worker command value must not be empty.");
                    end
                    value = rawCommand.value;
                end

                command = struct( ...
                    "kind", "channel", ...
                    "kindIndex", uint32(2), ...
                    "rawCommand", rawCommand, ...
                    "channel", channelName, ...
                    "action", actionName, ...
                    "value", value, ...
                    "stringCommand", "", ...
                    "stringCommandIndex", uint32(0), ...
                    "channelIndex", channelIndex, ...
                    "actionIndex", actionIndex);
                return;
            end

            if (isstring(rawCommand) && isscalar(rawCommand)) || ischar(rawCommand)
                stringCommand = obj.normalizeTextScalar_(rawCommand, "string command");
                command = struct( ...
                    "kind", "string", ...
                    "kindIndex", uint32(1), ...
                    "rawCommand", string(rawCommand), ...
                    "channel", "", ...
                    "action", "", ...
                    "value", [], ...
                    "stringCommand", stringCommand, ...
                    "stringCommandIndex", obj.instWorkerStringCommandIndex(stringCommand), ...
                    "channelIndex", uint32(0), ...
                    "actionIndex", uint32(0));
                return;
            end

            error("instrumentWorkerRuntime:InvalidCommand", ...
                "Worker command must be a struct or scalar string. Received:\n%s", ...
                formattedDisplayText(rawCommand));
        end

        function idx = lookupIndex_(obj, dict, name, label)
            name = obj.normalizeTextScalar_(name, label);
            try
                idx = dict(name);
            catch
                error("instrumentWorkerRuntime:UnknownName", ...
                    "Unknown %s for instrument worker %s: %s", ...
                    label, obj.requestedBy, name);
            end
        end

        function [dict, normalizedNames] = buildNameIndexDictionary_(obj, names, label)
            normalizedNames = string(names(:));
            if isempty(normalizedNames)
                dict = dictionary(string.empty(0, 1), uint32.empty(0, 1));
                return;
            end

            if any(strlength(normalizedNames) == 0)
                error("instrumentWorkerRuntime:InvalidNames", ...
                    "Instrument worker %s received an empty %s name.", obj.requestedBy, label);
            end
            if numel(unique(normalizedNames)) ~= numel(normalizedNames)
                error("instrumentWorkerRuntime:DuplicateNames", ...
                    "Instrument worker %s received duplicate %s names.", obj.requestedBy, label);
            end

            dict = dictionary(normalizedNames, uint32((1:numel(normalizedNames)).'));
        end

        function normalizedText = normalizeTextScalar_(obj, value, label)
            if isstring(value) && isscalar(value)
                normalizedText = value;
            elseif ischar(value)
                normalizedText = string(value);
            else
                error("instrumentWorkerRuntime:InvalidText", ...
                    "Instrument worker %s expected a scalar text %s. Received:\n%s", ...
                    obj.requestedBy, label, formattedDisplayText(value));
            end

            if strlength(normalizedText) == 0
                error("instrumentWorkerRuntime:InvalidText", ...
                    "Instrument worker %s expected a non-empty %s.", ...
                    obj.requestedBy, label);
            end
        end
    end
end
