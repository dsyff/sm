function smset(channelNames, values, ~)
% Wrapper around instrumentRack.rackSet.
%
% This function intentionally does NOT translate or expand channel names.
% It expects the raw channelFriendlyNames already used by the rack.
%
% Usage:
%   smset("chan", value)
%   smset(["ch1","ch2"], [v1; v2])
%
% Notes:
% - channelNames must be a 1-D list; it will be converted to a column vector.
% - values must be a numeric vector; it will be converted to a column vector.
% - Any rampRate third argument is accepted but ignored (rack controls ramping).

global engine %#ok<GVMIS>

if isempty(channelNames)
    return
end

hasEngine = exist("engine", "var") && ~isempty(engine) && isa(engine, "measurementEngine");
if ~hasEngine
    error("smset:no_backend", "No measurementEngine is available. Please run smready(...) first.")
end

if ~isstring(channelNames)
    error("smset:invalidChannels", "channelNames must be a string array.")
end

if ~isvector(channelNames)
    error("smset:invalidChannelsShape", "channelNames must be a 1-D string array.")
end

if ~isnumeric(values) || ~isvector(values)
    error("smset:invalidValues", "values must be a numeric vector.")
end

channelNames = channelNames(:);
values = values(:);
engine.rackSet(channelNames, values);
end

