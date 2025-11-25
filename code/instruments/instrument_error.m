classdef instrument_error < instrumentInterface
    % A test instrument that always errors on get/set operations
    % Used to test error handling and retry logic in instrumentRack

    methods
        function obj = instrument_error(address)
            obj@instrumentInterface();
            obj.address = address;
            obj.communicationHandle = [];
            
            % Add a test channel
            obj.addChannel("error_channel");
        end
        
        function delete(obj)
            % No handle to close
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            % Simulate a write error
            error("instrument_error:GetWriteError", "Simulated getWrite error for channel %d", channelIndex);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            % Simulate a read error
            error("instrument_error:GetReadError", "Simulated getRead error for channel %d", channelIndex);
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            % Simulate a set error
            error("instrument_error:SetWriteError", "Simulated setWrite error for channel %d", channelIndex);
        end
    end
end

