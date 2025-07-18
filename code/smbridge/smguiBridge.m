classdef smguiBridge < handle
    % Bridge class to adapt new instrumentRack system for legacy smgui_small
    % This allows the GUI to work with the new QMInstruments architecture
    % while maintaining compatibility with the old smdata structure
    
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
            smdata.configch = [];  % Configuration channels (empty by default)
            smdata.configfn = [];  % Configuration functions (empty by default)
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
                
                % Create datadim field - assumes all channels return scalar values (1x1)
                % This field specifies the dimensions of data returned by each channel
                % Format: [numChannels x 5] array where each row is [dim1, dim2, dim3, dim4, dim5]
                % For scalar channels, this is [1, 1, 1, 1, 1]
                instStruct(i).datadim = ones(numChannels, 5);
            end
        end
        
        function channelsStruct = createChannelsStruct(obj)
            % Create smdata.channels structure from instrumentRack channelTable
            channelsStruct = struct("name", {}, "instchan", {}, "rangeramp", {});
            
            if isempty(obj.rack.channelTable)
                return;
            end
            
            numChannels = height(obj.rack.channelTable);
            
            for i = 1:numChannels
                channelFriendlyName = obj.rack.channelTable.channelFriendlyNames(i);
                instrument = obj.rack.channelTable.instruments(i);
                
                % Find instrument index in instrumentTable
                instIdx = obj.findInstrumentIndex(instrument);
                
                channelsStruct(i).name = char(channelFriendlyName); % Convert to char for old interface
                channelsStruct(i).instchan = [instIdx, 1];  % Use 1 as default channel number for old interface
                
                % Default range/ramp values - can be customized later
                channelsStruct(i).rangeramp = [0, 0, 0, 1];  % [min, max, ramprate, conversion]
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
    end
end
