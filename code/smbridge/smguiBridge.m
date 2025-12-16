classdef smguiBridge < handle
    % Bridge class to adapt new instrumentRack system for legacy smgui_small
    % This allows the GUI to work with the new sm2 architecture
    % while maintaining compatibility with the old smdata structure
    
    properties (Access = public)
        experimentRootPath = ''  % Stores the root path for experiment data/ppt
    end
    
    properties (Access = private)
        rack  % The instrumentRack instance
    end
    
    methods
        function obj = smguiBridge(instrumentRack)
            % Constructor
            % Input: instrumentRack instance
            if nargin > 0 && isa(instrumentRack, 'instrumentRack')
                obj.rack = instrumentRack;
            else
                error('smguiBridge requires an instrumentRack instance');
            end
        end
        
        function initializeSmdata(obj)
            % Initialize the global smdata structure for GUI compatibility
            global smdata;
            
            % Create instruments structure from instrumentRack
            smdata.inst = obj.createInstStruct();
            
            % Create channels structure from instrumentRack channelTable
            smdata.channels = obj.createChannelsStruct();
            
            % Initialize optional fields for compatibility
            smdata.chanvals = [];  % Channel values cache (empty by default)
            smdata.options.skip_forced_ramp = false;  % Options structure with default values
        end
        
        function instStruct = createInstStruct(obj)
            % Create smdata.inst structure from instrumentRack
            instStruct = struct("name", {}, "cntrlfn", {}, "channels", {}, "datadim", {});
            
            if isempty(obj.rack.instrumentTable)
                return;
            end
            
            % Get unique instruments from the rack
            uniqueInstruments = obj.rack.instrumentTable.instruments;
            
            for i = 1:length(uniqueInstruments)
                inst = uniqueInstruments(i);
                instStruct(i).name = string(class(inst));
                
                % Create control function wrapper for old interface
                instStruct(i).cntrlfn = @(x) obj.instrumentWrapper(inst, x);
                
                % Get channel names from instrument
                try
                    channelNames = inst.getChannels();
                    instStruct(i).channels = string(channelNames);
                    numChannels = length(channelNames);
                catch
                    % Default channel names if getChannels not implemented
                    instStruct(i).channels = ["Ch1", "Ch2", "Ch3", "Ch4"];
                    numChannels = 4;
                end
                
                % Create datadim field - use actual channel sizes from instruments
                % This field specifies the dimensions of data returned by each channel
                % Format: [numChannels x 5] array where each row is [dim1, dim2, dim3, dim4, dim5]
                % For vector channels, first dimension indicates vector size
                instStruct(i).datadim = ones(numChannels, 5);
                
                % Update datadim with actual channel sizes for vector channels
                for chanIdx = 1:numChannels
                    try
                        channelSize = inst.findChannelSize(channelNames{chanIdx});
                        if channelSize > 1
                            instStruct(i).datadim(chanIdx, 1) = channelSize;
                        end
                    catch
                        % If findChannelSize fails, default to scalar (size 1)
                        instStruct(i).datadim(chanIdx, 1) = 1;
                    end
                end
            end
        end
        
        function channelsStruct = createChannelsStruct(obj)
            % Create smdata.channels structure from instrumentRack channelTable
            % Expands vector channels into individual scalar channels for plotting compatibility
            channelsStruct = struct("name", {}, "instchan", {}, "rangeramp", {});
            
            if isempty(obj.rack.channelTable)
                return;
            end
            
            numChannels = height(obj.rack.channelTable);
            scalarChannelIdx = 1;
            
            for i = 1:numChannels
                channelFriendlyName = obj.rack.channelTable.channelFriendlyNames(i);
                instrument = obj.rack.channelTable.instruments(i);
                channelSize = obj.rack.channelTable.channelSizes(i);
                
                % Find instrument index in instrumentTable
                instIdx = obj.findInstrumentIndex(instrument);
                
                if channelSize == 1
                    % Scalar channel - add directly
                    channelsStruct(scalarChannelIdx).name = char(channelFriendlyName);
                    channelsStruct(scalarChannelIdx).instchan = [instIdx, 1];
                    channelsStruct(scalarChannelIdx).rangeramp = [0, 0, 0, 1];
                    scalarChannelIdx = scalarChannelIdx + 1;
                else
                    % Vector channel - expand into scalar elements
                    for vecIdx = 1:channelSize
                        scalarName = sprintf("%s_%d", channelFriendlyName, vecIdx);
                        channelsStruct(scalarChannelIdx).name = char(scalarName);
                        channelsStruct(scalarChannelIdx).instchan = [instIdx, vecIdx];
                        channelsStruct(scalarChannelIdx).rangeramp = [0, 0, 0, 1];
                        scalarChannelIdx = scalarChannelIdx + 1;
                    end
                end
            end
        end
        
        function idx = findInstrumentIndex(obj, targetInstrument)
            % Find the index of an instrument in the instrumentTable
            idx = 1;  % Default to first instrument
            
            if isempty(obj.rack.instrumentTable)
                return;
            end
            
            for i = 1:height(obj.rack.instrumentTable)
                if obj.rack.instrumentTable.instruments(i) == targetInstrument
                    idx = i;
                    return;
                end
            end
        end
        
        function result = instrumentWrapper(obj, instrument, command)
            % Wrapper function to adapt new instrument interface to old cntrlfn format
            % command format: [instIdx, channelNum, action, value]
            % action: 0 = get, 1 = set
            
            try
                if length(command) >= 3
                    channelNum = command(2);
                    action = command(3);
                    
                    if action == 0  % Get operation
                        result = instrument.getValue(channelNum);
                    elseif action == 1 && length(command) >= 4  % Set operation
                        value = command(4);
                        instrument.setValue(channelNum, value);
                        result = value;
                    else
                        result = 0;
                    end
                else
                    result = 0;
                end
            catch ME
                warning("instrumentWrapper:error", "instrumentWrapper error: %s", ME.message);
                result = 0;
            end
        end
        
        function vectorChannelNames = getVectorChannelNames(obj)
            % Get vector channel names for efficient data acquisition
            % Returns only the original vector channel names (e.g., "XY", not "XY_1", "XY_2")
            vectorChannelNames = {};
            
            if isempty(obj.rack.channelTable)
                return;
            end
            
            numChannels = height(obj.rack.channelTable);
            for i = 1:numChannels
                channelFriendlyName = obj.rack.channelTable.channelFriendlyNames(i);
                vectorChannelNames{end+1} = char(channelFriendlyName);
            end
        end
        
        function scalarChannelNames = getScalarChannelNames(obj)
            % Get scalar channel names for plotting and data saving
            % Returns expanded channel names (e.g., "XY_1", "XY_2" for vector channels)
            scalarChannelNames = {};
            
            if isempty(obj.rack.channelTable)
                return;
            end
            
            numChannels = height(obj.rack.channelTable);
            for i = 1:numChannels
                channelFriendlyName = obj.rack.channelTable.channelFriendlyNames(i);
                channelSize = obj.rack.channelTable.channelSizes(i);
                
                if channelSize == 1
                    % Scalar channel
                    scalarChannelNames{end+1} = char(channelFriendlyName);
                else
                    % Vector channel - expand
                    for vecIdx = 1:channelSize
                        scalarName = sprintf("%s_%d", channelFriendlyName, vecIdx);
                        scalarChannelNames{end+1} = char(scalarName);
                    end
                end
            end
        end
        
        function pureScalarChannelNames = getPureScalarChannelNames(obj)
            % Get only inherently scalar channel names (channelSize == 1)
            % Used for set channel dropdowns - excludes expanded vector components
            pureScalarChannelNames = {};
            
            if isempty(obj.rack.channelTable)
                return;
            end
            
            numChannels = height(obj.rack.channelTable);
            for i = 1:numChannels
                channelFriendlyName = obj.rack.channelTable.channelFriendlyNames(i);
                channelSize = obj.rack.channelTable.channelSizes(i);
                
                if channelSize == 1
                    % Only scalar channels (not expanded vector components)
                    pureScalarChannelNames{end+1} = char(channelFriendlyName);
                end
            end
        end
        
        function channelSize = getChannelSize(obj, channelFriendlyName)
            % Get the size of a channel by its friendly name
            % Returns 1 for scalar channels, >1 for vector channels
            if isempty(obj.rack.channelTable)
                error('Channel table is empty');
            end
            
            channelIdx = find(strcmp(obj.rack.channelTable.channelFriendlyNames, channelFriendlyName), 1);
            if isempty(channelIdx)
                error('Channel "%s" not found', channelFriendlyName);
            end
            
            channelSize = obj.rack.channelTable.channelSizes(channelIdx);
        end
    end
end
