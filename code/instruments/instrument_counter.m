classdef instrument_counter < instrumentInterface
    % genAI
    % Implements a single channel 'count' that stores and returns the last set value.

    properties (Access = private)
        storedCount double = 0;
    end

    methods
        function obj = instrument_counter(address)
            % Constructor: add 'count' channel (scalar)
            obj@instrumentInterface();
            obj.address = address;  % Set address from constructor argument
            obj.addChannel("count", 1, setTolerances = 1E-9);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No hardware action needed for counter
            % This method is required by interface
        end
        
        function setWriteChannelHelper(obj, ~, setValues)
            % Store the set value for 'count' channel
            obj.storedCount = setValues;
        end
        
        function getValues = getReadChannelHelper(obj, ~)
            % Return the stored count value
            getValues = obj.storedCount;
        end
    end
end
