classdef instrumentRackEditPatch
    properties (SetAccess = private)
        entries table = table( ...
            Size = [0, 5], ...
            VariableTypes = ["string", "cell", "cell", "cell", "cell"], ...
            VariableNames = ["channelFriendlyName", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"])
    end

    methods
        function obj = instrumentRackEditPatch(entries)
            if nargin < 1
                return;
            end
            if ~istable(entries)
                error("instrumentRackEditPatch:InvalidEntries", "entries must be a table.");
            end

            required = ["channelFriendlyName", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"];
            if ~all(ismember(required, string(entries.Properties.VariableNames)))
                error("instrumentRackEditPatch:InvalidEntries", ...
                    "entries must include: %s.", strjoin(required, ", "));
            end
            entries = entries(:, required);

            channelNames = string(entries.channelFriendlyName(:));
            if any(ismissing(channelNames) | strlength(channelNames) == 0)
                error("instrumentRackEditPatch:InvalidEntries", "channelFriendlyName values must be non-empty strings.");
            end
            if numel(unique(channelNames)) ~= numel(channelNames)
                error("instrumentRackEditPatch:DuplicateChannel", "channelFriendlyName rows must be unique.");
            end
            entries.channelFriendlyName = channelNames;

            vectorFields = required(2:end);
            for field = vectorFields
                values = entries.(field);
                if ~iscell(values) || ~iscolumn(values)
                    error("instrumentRackEditPatch:InvalidEntries", "%s must be an N-by-1 cell column.", field);
                end
                for i = 1:numel(values)
                    v = values{i};
                    if ~(isnumeric(v) && isvector(v) && isreal(v))
                        error("instrumentRackEditPatch:InvalidEntries", ...
                            "%s for channel %s must be a real numeric vector.", field, channelNames(i));
                    end
                    values{i} = double(v(:));
                end
                entries.(field) = values;
            end

            obj.entries = entries;
        end

        function tf = isEmpty(obj)
            tf = height(obj.entries) == 0;
        end

        function n = numEntries(obj)
            n = height(obj.entries);
        end
    end
end
