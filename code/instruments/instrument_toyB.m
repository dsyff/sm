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
            channel = obj.channelTable.channels(channelIndex);
            switch channel
                case "X"
                    obj.storedX = setValues;
                case "Y"
                    obj.storedY = setValues;
                otherwise
                    error('Unknown channel: %s', channel);
            end
        end
        
        function getValues = getReadChannelHelper(obj, channelIndex)
            % Return the stored values for the specified channel
            channel = obj.channelTable.channels(channelIndex);
            switch channel
                case "X"
                    getValues = obj.storedX;
                case "Y"
                    getValues = obj.storedY;
                otherwise
                    error('Unknown channel: %s', channel);
            end
        end
    end
end
