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
            switch channelIndex
                case 1
                    obj.storedA = setValues;
                case 2
                    obj.storedB = setValues;
                otherwise
                    channel = obj.channelTable.channels(channelIndex);
                    error('Unknown channel: %s', channel);
            end
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Return the stored values for the specified channel
            switch channelIndex
                case 1
                    getValues = obj.storedA;
                case 2
                    getValues = obj.storedB;
                otherwise
                    channel = obj.channelTable.channels(channelIndex);
                    error('Unknown channel: %s', channel);
            end
        end
    end
end
