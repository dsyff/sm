classdef instrument_toyA < instrumentInterface
    % Toy instrument A with multiple channels for testing
    % Channel 'A': scalar (size 1)
    % Channel 'B': vector (size 3)

    properties (Access = private)
        storedA double = 0;
        storedB double = [0; 0; 0];
    end

    methods
        function obj = instrument_toyA(address)
            % Constructor: add channels
            obj@instrumentInterface();
            obj.address = address;  % Set address from constructor argument
            obj.addChannel("A", 1);
            obj.addChannel("B", 3);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No hardware action needed for toy instrument
        end
        
        function setWriteChannelHelper(obj, channelIndex, setValues)
            % Store the set values for the specified channel
            channel = obj.channelTable.channels(channelIndex);
            switch channel
                case "A"
                    obj.storedA = setValues;
                case "B"
                    obj.storedB = setValues;
                otherwise
                    error('Unknown channel: %s', channel);
            end
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Return the stored values for the specified channel
            channel = obj.channelTable.channels(channelIndex);
            switch channel
                case "A"
                    getValues = obj.storedA;
                case "B"
                    getValues = obj.storedB;
                otherwise
                    error('Unknown channel: %s', channel);
            end
        end
    end
end
