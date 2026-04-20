classdef instrument_toyB < instrumentInterface
    % Toy instrument B with multiple channels for testing
    % Channel 'X': vector (size 2)
    % Channel 'Y': vector (size 4)

    properties (Access = private)
        storedX double = [0; 0];
        storedY double = [0; 0; 0; 0];
    end

    methods
        function obj = instrument_toyB(address)
            % Constructor: add channels
            obj@instrumentInterface();
            obj.address = address;  % Set address from constructor argument
            obj.addChannel("X", 2);
            obj.addChannel("Y", 4);
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
                    obj.storedX = setValues;
                case 2
                    obj.storedY = setValues;
                otherwise
                    channel = obj.channelTable.channels(channelIndex);
                    error('Unknown channel: %s', channel);
            end
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Return the stored values for the specified channel
            switch channelIndex
                case 1
                    getValues = obj.storedX;
                case 2
                    getValues = obj.storedY;
                otherwise
                    channel = obj.channelTable.channels(channelIndex);
                    error('Unknown channel: %s', channel);
            end
        end
    end
end
