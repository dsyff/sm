function values = smget(channelNames)
% Wrapper around instrumentRack.rackGet.
%
% This function intentionally does NOT translate or expand channel names.
% It expects the raw channelFriendlyNames already used by the rack.
%
% Usage:
%   values = smget("chan")
%   values = smget(["ch1","ch2"])
%
% Notes:
% - channelNames must be a 1-D list; it will be converted to a column vector.
% - values is the raw numeric column vector returned by rackGet (concatenated).

global engine %#ok<GVMIS>

if isempty(channelNames)
    values = [];
    return
end

hasEngine = exist("engine", "var") && ~isempty(engine) && isa(engine, "measurementEngine");
if ~hasEngine
    error("smget:no_backend", "No measurementEngine is available. Please run smready(...) first.")
end

if ~isstring(channelNames)
    error("smget:invalidChannels", "channelNames must be a string array.")
end

if ~isvector(channelNames)
    error("smget:invalidChannelsShape", "channelNames must be a 1-D string array.")
end

channelNames = channelNames(:);
values = engine.rackGet(channelNames);
values = values(:);
end
