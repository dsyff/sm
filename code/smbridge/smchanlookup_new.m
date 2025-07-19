function channelIndices = smchanlookup_new(channelNames, vector_name)
% Modern version of smchanlookup for new system with vector channel support
% Returns 1-based indices for given channel names
%
% Usage:
%   idx = smchanlookup_new('ChannelName', true)      % Vector name lookup (GUI display names)
%   idx = smchanlookup_new('ChannelName', false)     % Scalar name lookup (smdata.channels names)
%   idx = smchanlookup_new({'Ch1', 'Ch2'}, true)     % Multiple vector names
%   idx = smchanlookup_new(["Ch1", "Ch2"], false)    % Multiple scalar names
%   idx = smchanlookup_new([], true/false)           % Empty array - returns []
%
% Parameters:
%   channelNames - Channel name(s) to look up (char, string, cell array, or string array)
%   vector_name  - Boolean flag:
%                  true:  Look up vector names (e.g., 'vector_chan') and expand to scalar indices
%                  false: Look up scalar names directly (e.g., 'vector_chan_1', 'vector_chan_2')

global smdata bridge;

% Validate required parameter
if nargin < 2
    error('smchanlookup_new requires two arguments: channelNames and vector_name flag');
end

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

% For vector channel support, we need to look up in the appropriate channel context
% vector_name=true:  Look up vector names and expand to scalar indices
% vector_name=false: Look up scalar names directly in smdata.channels

% Handle single channel name case
if ischar(channelNames) || (isstring(channelNames) && isscalar(channelNames))
    channelName = string(channelNames);
    
    if vector_name
        % Vector name lookup - expand to scalar components if needed
        % Require bridge for vector channel support
        if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
            error('smguiBridge is required but not available. Cannot lookup vector channel names.');
        end
        
        % Check if this is a vector channel and expand it
        try
            channelSize = bridge.getChannelSize(channelName);
            if channelSize > 1
                % Vector channel - expand to scalar components and look up in smdata.channels
                scalarNames = {};
                for k = 1:channelSize
                    scalarNames{end+1} = sprintf("%s_%d", channelName, k);
                end
                
                % Look up each scalar component in smdata.channels
                channelIndices = zeros(1, channelSize);
                for k = 1:channelSize
                    found = false;
                    for j = 1:length(smdata.channels)
                        if strcmp(string(smdata.channels(j).name), scalarNames{k})
                            channelIndices(k) = j;
                            found = true;
                            break;
                        end
                    end
                    if ~found
                        error('Expanded scalar channel "%s" not found in smdata.channels', scalarNames{k});
                    end
                end
                return;
            else
                % Pure scalar channel - look up directly in smdata.channels
                for j = 1:length(smdata.channels)
                    if strcmp(string(smdata.channels(j).name), channelName)
                        channelIndices = j;
                        return;
                    end
                end
                error('Channel "%s" not found in smdata.channels', channelName);
            end
        catch ME
            error('Failed to lookup vector channel "%s": %s', channelName, ME.message);
        end
    else
        % Scalar name lookup - look up directly in smdata.channels
        for j = 1:length(smdata.channels)
            if strcmp(string(smdata.channels(j).name), channelName)
                channelIndices = j;
                return;
            end
        end
        error('Scalar channel "%s" not found in smdata.channels', channelName);
    end
end

% Handle multiple channel names
if isstring(channelNames)
    channelNames = channelNames;
elseif iscell(channelNames)
    channelNames = string(channelNames);
else
    error("Invalid input type for channelNames");
end

if vector_name
    % Vector name lookup - expand vector channels and collect all scalar indices
    % Require bridge for vector channel support
    if ~exist('bridge', 'var') || isempty(bridge) || ~isa(bridge, 'smguiBridge')
        error('smguiBridge is required but not available. Cannot lookup vector channel names.');
    end
    
    % Expand all vector channels and collect all scalar indices
    allScalarIndices = [];
    
    for i = 1:length(channelNames)
        channelName = channelNames(i);
        
        % Check if this is a vector channel and expand it
        try
            channelSize = bridge.getChannelSize(channelName);
            if channelSize > 1
                % Vector channel - expand to scalar components and look up in smdata.channels
                for k = 1:channelSize
                    scalarName = sprintf("%s_%d", channelName, k);
                    found = false;
                    for j = 1:length(smdata.channels)
                        if strcmp(string(smdata.channels(j).name), scalarName)
                            allScalarIndices(end+1) = j;
                            found = true;
                            break;
                        end
                    end
                    if ~found
                        error('Expanded scalar channel "%s" not found in smdata.channels', scalarName);
                    end
                end
            else
                % Pure scalar channel - look up directly in smdata.channels
                found = false;
                for j = 1:length(smdata.channels)
                    if strcmp(string(smdata.channels(j).name), channelName)
                        allScalarIndices(end+1) = j;
                        found = true;
                        break;
                    end
                end
                if ~found
                    error('Channel "%s" not found in smdata.channels', channelName);
                end
            end
        catch ME
            error('Failed to lookup vector channel "%s": %s', channelName, ME.message);
        end
    end
    
    channelIndices = allScalarIndices;
else
    % Scalar name lookup - look up each name directly in smdata.channels
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
            error("Scalar channel %s not found", channelNames(i));
        end
    end
end
end
