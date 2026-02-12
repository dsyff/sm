classdef smguiBridge < handle
    % Bridge class to adapt new instrumentRack system for legacy smgui_small
    % This allows the GUI to work with the new sm2 architecture
    % while maintaining compatibility with the old smdata structure
    
    properties (Access = public)
        experimentRootPath = ''  % Stores the root path for experiment data/ppt
    end
    
    properties (Access = private)
        rack = instrumentRack.empty(0, 1)
        engine = measurementEngine.empty(0, 1)
        channelFriendlyNames (:, 1) string = string.empty(0, 1)
        channelSizes (:, 1) double = double.empty(0, 1)
    end
    
    methods
        function obj = smguiBridge(source)
            % Constructor
            % Input: measurementEngine or instrumentRack instance
            if nargin == 0
                return;
            end

            if isa(source, "measurementEngine")
                obj.engine = source;
                if source.constructionMode == "rack" && ~isempty(source.rackLocal)
                    obj.rack = source.rackLocal;
                end
                [names, sizes] = source.getChannelMetadata();
                obj.channelFriendlyNames = string(names(:));
                obj.channelSizes = double(sizes(:));
                return;
            end

            if isa(source, "instrumentRack")
                obj.rack = source;
                if ~isempty(source.channelTable)
                    obj.channelFriendlyNames = string(source.channelTable.channelFriendlyNames(:));
                    obj.channelSizes = double(source.channelTable.channelSizes(:));
                end
                return;
            end

            error("smguiBridge:InvalidSource", "smguiBridge requires a measurementEngine or instrumentRack instance.");
        end
        
        function initializeSmdata(obj)
            % Initialize the global smdata structure for GUI compatibility
            global smdata %#ok<GVMIS>
            
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
            
            if isempty(obj.rack) || isempty(obj.rack.instrumentTable)
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
            channelsStruct = struct("name", {}, "instchan", {}, "rangeramp", {});

            if isempty(obj.channelFriendlyNames)
                return;
            end

            scalarChannelIdx = 1;
            for i = 1:numel(obj.channelFriendlyNames)
                channelFriendlyName = obj.channelFriendlyNames(i);
                channelSize = obj.channelSizes(i);

                if channelSize == 1
                    channelsStruct(scalarChannelIdx).name = char(channelFriendlyName);
                    channelsStruct(scalarChannelIdx).instchan = [1, 1];
                    channelsStruct(scalarChannelIdx).rangeramp = [0, 0, 0, 1];
                    scalarChannelIdx = scalarChannelIdx + 1;
                else
                    for vecIdx = 1:channelSize
                        scalarName = channelFriendlyName + "_" + vecIdx;
                        channelsStruct(scalarChannelIdx).name = char(scalarName);
                        channelsStruct(scalarChannelIdx).instchan = [1, vecIdx];
                        channelsStruct(scalarChannelIdx).rangeramp = [0, 0, 0, 1];
                        scalarChannelIdx = scalarChannelIdx + 1;
                    end
                end
            end
        end
        
        function idx = findInstrumentIndex(obj, targetInstrument)
            % Find the index of an instrument in the instrumentTable
            idx = 1;  % Default to first instrument
            
            if isempty(obj.rack) || isempty(obj.rack.instrumentTable)
                return;
            end
            
            for i = 1:height(obj.rack.instrumentTable)
                if obj.rack.instrumentTable.instruments(i) == targetInstrument
                    idx = i;
                    return;
                end
            end
        end
        
        function result = instrumentWrapper(~, instrument, command)
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
            vectorChannelNames = cellstr(obj.channelFriendlyNames);
        end
        
        function scalarChannelNames = getScalarChannelNames(obj)
            % Get scalar channel names for plotting and data saving
            % Returns expanded channel names (e.g., "XY_1", "XY_2" for vector channels)
            scalarChannelNames = {};
            for i = 1:numel(obj.channelFriendlyNames)
                channelFriendlyName = obj.channelFriendlyNames(i);
                channelSize = obj.channelSizes(i);
                if channelSize == 1
                    scalarChannelNames{end+1} = char(channelFriendlyName);
                else
                    for vecIdx = 1:channelSize
                        scalarChannelNames{end+1} = char(channelFriendlyName + "_" + vecIdx);
                    end
                end
            end
        end
        
        function pureScalarChannelNames = getPureScalarChannelNames(obj)
            % Get only inherently scalar channel names (channelSize == 1)
            % Used for set channel dropdowns - excludes expanded vector components
            pureScalarChannelNames = {};
            for i = 1:numel(obj.channelFriendlyNames)
                if obj.channelSizes(i) == 1
                    pureScalarChannelNames{end+1} = char(obj.channelFriendlyNames(i));
                end
            end
        end
        
        function channelSize = getChannelSize(obj, channelFriendlyName)
            % Get the size of a channel by its friendly name
            % Returns 1 for scalar channels, >1 for vector channels
            channelFriendlyName = string(channelFriendlyName);
            channelIdx = find(obj.channelFriendlyNames == channelFriendlyName, 1);
            if isempty(channelIdx)
                error('Channel "%s" not found', channelFriendlyName);
            end
            channelSize = obj.channelSizes(channelIdx);
        end
    end
end
