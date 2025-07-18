function data = smget_new(channels)
% Modern smget function that works with instrumentRack (optimized for performance)
% This replaces the old smget function to work with the new sm2
%
% Usage: data = smget_new(channels)
% channels: string array of channel names or numeric channel indices
% data: cell array of values read from instruments

global smdata instrumentRackGlobal;

if isempty(channels)
    data = {};
    return
end

% Convert channel names to indices if needed
if ~isnumeric(channels)
    channels = smchanlookup_new(channels, true);
end

% Ensure channels is a numeric vector
if iscell(channels)
    channels = cell2mat(channels);
end

nchan = length(channels);

% Performance optimization: pre-allocate data cell array
data = cell(1, nchan);

% Use instrumentRack if available
if exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal)
    % Performance optimization: pre-allocate and cache smdata.channels length
    smdata_channels_length = length(smdata.channels);
    channelNames = strings(nchan, 1);

    % Performance optimization: vectorized channel name lookup
    for i = 1:nchan
        if channels(i) <= smdata_channels_length
            channelNames(i) = string(smdata.channels(channels(i)).name);
        else
            error("Channel index %d out of range", channels(i));
        end
    end

    % Use instrumentRack for getting values (bulk read for performance)
    values = instrumentRackGlobal.rackGet(channelNames);

    % Performance optimization: direct assignment instead of loop
    data = num2cell(values);
    return;
else
    error("smget_new:no_instrumentRack", "instrumentRackGlobal is not available. Cannot get values.");
end
end
