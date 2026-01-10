function smset_new(channelNames, values, ~)
% Wrapper around instrumentRack.rackSet.
%
% This function intentionally does NOT translate or expand channel names.
% It expects the raw channelFriendlyNames already used by the rack.
%
% Usage:
%   smset_new("chan", value)
%   smset_new(["ch1","ch2"], [v1; v2])
%   smset_new({"ch1","ch2"}, [v1; v2])
%
% Notes:
% - channelNames must be a 1-D list; it will be converted to a column vector.
% - values must be a numeric vector; it will be converted to a column vector.
% - Any rampRate third argument is accepted but ignored (rack controls ramping).

global instrumentRackGlobal

if isempty(channelNames)
    return
end

if ~(exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal))
    error("smset_new:no_instrumentRack", "instrumentRackGlobal is not available. Cannot set values.")
end

if ischar(channelNames)
    channelNames = string(channelNames);
elseif iscell(channelNames)
    channelNames = string(channelNames);
elseif ~isstring(channelNames)
    error("smset_new:invalidChannels", "channelNames must be string/cellstr/char.")
end

if ~isvector(channelNames)
    error("smset_new:invalidChannelsShape", "channelNames must be a 1-D string array.")
end

if ~isnumeric(values) || ~isvector(values)
    error("smset_new:invalidValues", "values must be a numeric vector.")
end

channelNames = channelNames(:);
values = values(:);
instrumentRackGlobal.rackSet(channelNames, values);
end

