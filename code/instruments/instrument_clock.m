classdef instrument_clock < instrumentInterface
    % genAI
    % Implements a single channel 'timeStamp' that returns the current time in seconds (with milliseconds) since epoch.

    methods
        function obj = instrument_clock(address)
            % Constructor: add 'timeStamp' channel (scalar)
            obj@instrumentInterface();
            obj.address = address;  % Set address from constructor argument
            obj.addChannel("timeStamp", 1);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No hardware action needed for clock
        end
        
        function setWriteChannelHelper(~, ~, ~)
            % Setting timeStamp is not supported
            error('Setting the timeStamp channel is not supported.');
        end
        
        function getValues = getReadChannelHelper(~, ~)
            % Return the current time in seconds since epoch
            getValues = posixtime(datetime('now'));
        end
    end
end
