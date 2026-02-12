classdef instrument_toyFprintf < instrumentInterface
    % Minimal toy instrument to test worker fprintf forwarding.

    properties (Access = private)
        storedValue (1, 1) double = 0
    end

    methods
        function obj = instrument_toyFprintf(address)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
            end

            obj@instrumentInterface();
            obj.address = address;
            obj.requireSetCheck = false;
            obj.addChannel("value");
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No hardware action needed.
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex ~= 1
                error("instrument_toyFprintf:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            experimentContext.print("[toyFprintf] set value=%g", setValues(1));
            obj.storedValue = setValues(1);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex ~= 1
                error("instrument_toyFprintf:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            experimentContext.print("[toyFprintf] get value=%g", obj.storedValue);
            getValues = obj.storedValue;
        end
    end
end

