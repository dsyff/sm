classdef instrumentRackRecipe < handle
    % Recipe for constructing an instrumentRack on a worker.
    %
    % The recipe is serializable and contains only construction instructions.

    properties (SetAccess = private)
        instrumentSteps (1, :) struct = struct( ...
            "handleVar", {}, ...
            "className", {}, ...
            "friendlyName", {}, ...
            "positionalArgs", {}, ...
            "nameValuePairs", {}, ...
            "numeWorkersRequested", {});

        virtualInstrumentSteps (1, :) struct = struct( ...
            "handleVar", {}, ...
            "className", {}, ...
            "friendlyName", {}, ...
            "positionalArgs", {}, ...
            "nameValuePairs", {}, ...
            "numeWorkersRequested", {});

        channelSteps (1, :) struct = struct( ...
            "instrumentFriendlyName", {}, ...
            "channel", {}, ...
            "channelFriendlyName", {}, ...
            "rampRates", {}, ...
            "rampThresholds", {}, ...
            "softwareMins", {}, ...
            "softwareMaxs", {});

        statements (1, :) struct = struct( ...
            "instrumentFriendlyName", {}, ...
            "codeString", {})
    end

    methods
        function addInstrument(obj, handleVar, className, friendlyName, varargin)
            arguments
                obj
                handleVar (1, 1) string {mustBeNonzeroLengthText}
                className (1, 1) string {mustBeNonzeroLengthText}
                friendlyName (1, 1) string {mustBeNonzeroLengthText}
            end
            arguments (Repeating)
                varargin
            end

            if ~isvarname(char(handleVar))
                error("instrumentRackRecipe:InvalidHandleVar", "handleVar must be a valid variable name. Received: %s", handleVar);
            end
            if instrumentRackRecipe.isVirtualInstrumentClass_(className)
                error("instrumentRackRecipe:VirtualInstrumentNotAllowed", ...
                    "Class %s is a virtual instrument. Use addVirtualInstrument(...) instead of addInstrument(...).", className);
            end

            [positionalArgs, nameValuePairs] = instrumentRackRecipe.splitArgs_(varargin);

            % Extract recipe-specific name-values (and remove them from instrument constructor nvpairs).
            numeWorkersRequested = [];
            if ~isempty(nameValuePairs)
                keys = string(nameValuePairs(1:2:end));
                if any(strcmpi(keys, "numWorkersRequired"))
                    error("instrumentRackRecipe:WorkersKeyRenamed", ...
                        "Recipe key numWorkersRequired has been renamed to numeWorkersRequested.");
                end
                isWorkersKey = strcmpi(keys, "numeWorkersRequested");
                if any(isWorkersKey)
                    if nnz(isWorkersKey) > 1
                        error("instrumentRackRecipe:DuplicateWorkersRequested", "numeWorkersRequested provided more than once.");
                    end
                    idx = find(isWorkersKey, 1, "first");
                    numeWorkersRequested = double(nameValuePairs{2*idx});
                    nameValuePairs(2*idx-1:2*idx) = [];
                end
            end

            if isempty(numeWorkersRequested)
                numeWorkersRequested = 0;
            end
            if ~(isscalar(numeWorkersRequested) && isfinite(numeWorkersRequested) && numeWorkersRequested >= 0 && mod(numeWorkersRequested, 1) == 0)
                error("instrumentRackRecipe:InvalidWorkersRequested", "numeWorkersRequested must be a nonnegative integer. Received: %s", formattedDisplayText(numeWorkersRequested));
            end

            step = struct();
            step.handleVar = handleVar;
            step.className = className;
            step.friendlyName = friendlyName;
            step.positionalArgs = positionalArgs;
            step.nameValuePairs = nameValuePairs;
            step.numeWorkersRequested = numeWorkersRequested;
            obj.instrumentSteps(end+1) = step;
        end

        function addVirtualInstrument(obj, handleVar, className, friendlyName, varargin)
            arguments
                obj
                handleVar (1, 1) string {mustBeNonzeroLengthText}
                className (1, 1) string {mustBeNonzeroLengthText}
                friendlyName (1, 1) string {mustBeNonzeroLengthText}
            end
            arguments (Repeating)
                varargin
            end

            if ~isvarname(char(handleVar))
                error("instrumentRackRecipe:InvalidHandleVar", "handleVar must be a valid variable name. Received: %s", handleVar);
            end
            if ~instrumentRackRecipe.isVirtualInstrumentClass_(className)
                error("instrumentRackRecipe:NonVirtualInstrumentNotAllowed", ...
                    "Class %s is not a virtual instrument. Use addInstrument(...) instead of addVirtualInstrument(...).", className);
            end

            [positionalArgs, nameValuePairs] = instrumentRackRecipe.splitArgs_(varargin);
            if isempty(positionalArgs)
                positionalArgs = {friendlyName};
            end

            numeWorkersRequested = [];
            if ~isempty(nameValuePairs)
                keys = string(nameValuePairs(1:2:end));
                if any(strcmpi(keys, "numWorkersRequired"))
                    error("instrumentRackRecipe:WorkersKeyRenamed", ...
                        "Recipe key numWorkersRequired has been renamed to numeWorkersRequested.");
                end
                isWorkersKey = strcmpi(keys, "numeWorkersRequested");
                if any(isWorkersKey)
                    if nnz(isWorkersKey) > 1
                        error("instrumentRackRecipe:DuplicateWorkersRequested", "numeWorkersRequested provided more than once.");
                    end
                    idx = find(isWorkersKey, 1, "first");
                    numeWorkersRequested = double(nameValuePairs{2*idx});
                    nameValuePairs(2*idx-1:2*idx) = [];
                end
            end
            if isempty(numeWorkersRequested)
                numeWorkersRequested = 0;
            end
            if ~(isscalar(numeWorkersRequested) && isfinite(numeWorkersRequested) && numeWorkersRequested >= 0 && mod(numeWorkersRequested, 1) == 0)
                error("instrumentRackRecipe:InvalidWorkersRequested", "numeWorkersRequested must be a nonnegative integer. Received: %s", formattedDisplayText(numeWorkersRequested));
            end

            step = struct();
            step.handleVar = handleVar;
            step.className = className;
            step.friendlyName = friendlyName;
            step.positionalArgs = positionalArgs;
            step.nameValuePairs = nameValuePairs;
            step.numeWorkersRequested = numeWorkersRequested;
            obj.virtualInstrumentSteps(end+1) = step;
        end

        function addChannel(obj, instrumentFriendlyName, channel, channelFriendlyName, rampRates, rampThresholds, softwareMins, softwareMaxs)
            arguments
                obj
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText}
                channel (1, 1) string {mustBeNonzeroLengthText}
                channelFriendlyName (1, 1) string {mustBeNonzeroLengthText}
                rampRates double = []
                rampThresholds double = []
                softwareMins double = []
                softwareMaxs double = []
            end

            step = struct();
            step.instrumentFriendlyName = instrumentFriendlyName;
            step.channel = channel;
            step.channelFriendlyName = channelFriendlyName;
            step.rampRates = rampRates;
            step.rampThresholds = rampThresholds;
            step.softwareMins = softwareMins;
            step.softwareMaxs = softwareMaxs;
            obj.channelSteps(end+1) = step;
        end

        function addStatement(obj, instrumentFriendlyName, codeString)
            arguments
                obj
                instrumentFriendlyName (1, 1) string {mustBeNonzeroLengthText}
                codeString (1, 1) string {mustBeNonzeroLengthText}
            end
            step = struct();
            step.instrumentFriendlyName = instrumentFriendlyName;
            step.codeString = codeString;
            obj.statements(end+1) = step;
        end

        function n = totalWorkersRequired(obj)
            % Total *instrument* workers required (excluding the engine worker).
            n = 0;
            for k = 1:numel(obj.instrumentSteps)
                n = n + double(obj.instrumentSteps(k).numeWorkersRequested);
            end
            for k = 1:numel(obj.virtualInstrumentSteps)
                n = n + double(obj.virtualInstrumentSteps(k).numeWorkersRequested);
            end
        end
    end

    methods (Static, Access = private)
        function TF = isVirtualInstrumentClass_(className)
            className = string(className);
            if className == "virtualInstrumentInterface"
                TF = true;
                return;
            end
            try
                sc = string(superclasses(char(className)));
            catch
                error("instrumentRackRecipe:UnknownClass", ...
                    "Cannot resolve class %s on the MATLAB path. Add the code folder to the path before building a recipe.", className);
            end
            TF = any(sc == "virtualInstrumentInterface");
        end

        function [positionalArgs, nameValuePairs] = splitArgs_(args)
            % Split {positional..., name,value,...} by detecting the first valid NV block.
            positionalArgs = args;
            nameValuePairs = {};
            if isempty(args)
                return;
            end

            nvStart = [];
            for k = 1:numel(args)
                tail = args(k:end);
                if mod(numel(tail), 2) ~= 0
                    continue;
                end
                keys = tail(1:2:end);
                if all(cellfun(@(x) (isstring(x) && isscalar(x)) || ischar(x), keys))
                    nvStart = k;
                    break;
                end
            end

            if isempty(nvStart)
                return;
            end

            positionalArgs = args(1:nvStart-1);
            nameValuePairs = args(nvStart:end);
        end
    end
end

