function values = smget_new(channelNames)
% Wrapper around instrumentRack.rackGet.
%
% This function intentionally does NOT translate or expand channel names.
% It expects the raw channelFriendlyNames already used by the rack.
%
% Usage:
%   values = smget_new("chan")
%   values = smget_new(["ch1","ch2"])
%
% Notes:
% - channelNames must be a 1-D list; it will be converted to a column vector.
% - values is the raw numeric column vector returned by rackGet (concatenated).

global instrumentRackGlobal

if isempty(channelNames)
    values = [];
    return
end

if ~(exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal))
    error("smget_new:no_instrumentRack", "instrumentRackGlobal is not available. Cannot get values.")
end

if ~isstring(channelNames)
    error("smget_new:invalidChannels", "channelNames must be a string array.")
end

if ~isvector(channelNames)
    error("smget_new:invalidChannelsShape", "channelNames must be a 1-D string array.")
end

channelNames = channelNames(:);
values = instrumentRackGlobal.rackGet(channelNames);
values = values(:);
end
