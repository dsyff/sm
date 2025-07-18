function channelIndices = smchanlookup_new(channelNames)
% Modern version of smchanlookup for new system
% Returns 1-based channel indices for given channel names
%
% Usage:
%   idx = smchanlookup_new('ChannelName')     % Single channel
%   idx = smchanlookup_new({'Ch1', 'Ch2'})    % Multiple channels
%   idx = smchanlookup_new(["Ch1", "Ch2"])    % String array
%   idx = smchanlookup_new([])                % Empty array - returns []

global smdata;

% Handle empty input
if isempty(channelNames)
    channelIndices = [];
    return;
end

% Handle numeric indices (already valid channel numbers)
if isnumeric(channelNames)
    channelIndices = channelNames;
    return;
end

% Handle single channel name case
if ischar(channelNames) || (isstring(channelNames) && isscalar(channelNames))
    % Single channel lookup
    channelName = string(channelNames);
    
    for j = 1:length(smdata.channels)
        % Handle both string and char comparisons
        storedName = string(smdata.channels(j).name);
        if strcmp(storedName, channelName)
            channelIndices = j;
            return;
        end
    end
    error("Channel %s not found", channelName);
end

% Handle multiple channel names
if isstring(channelNames)
    channelNames = channelNames;
elseif iscell(channelNames)
    channelNames = string(channelNames);
else
    error("Invalid input type for channelNames");
end

channelIndices = zeros(size(channelNames));

for i = 1:length(channelNames)
    found = false;
    for j = 1:length(smdata.channels)
        % Handle both string and char comparisons
        storedName = string(smdata.channels(j).name);
        if strcmp(storedName, channelNames(i))
            channelIndices(i) = j;
            found = true;
            break;
        end
    end
    if ~found
        error("Channel %s not found", channelNames(i));
    end
end
end
