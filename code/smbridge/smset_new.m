function smset_new(channels, vals, ~)
% Modern smset function that works with instrumentRack
% This replaces the old smset function to work with the new sm2
%
% Usage: smset_new(channels, vals, ramprate)
% channels: string array of channel names or numeric channel indices
% vals: values to set (vector)
% ramprate: ramping rate (ignored for performance optimization - use ~ placeholder)

global smdata instrumentRackGlobal;

if isempty(channels)
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

% Handle values
if size(vals, 2) > 1
    vals = vals';
end

if length(vals) == 1
    vals = vals * ones(nchan, 1);
end

% Use instrumentRack
if exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal)
    % Get channel names from indices
    channelNames = strings(nchan, 1);
    for i = 1:nchan
        if channels(i) <= length(smdata.channels)
            channelNames(i) = string(smdata.channels(channels(i)).name);
        else
            error("Channel index %d out of range", channels(i));
        end
    end
    
    % Use instrumentRack for setting (ramping removed for performance)
    instrumentRackGlobal.rackSetWrite(channelNames, vals);
    return;
else
    error("instrumentRackGlobal is not available. Cannot set values.");
end


end
