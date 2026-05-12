classdef instrument_rampTrace < instrumentInterface
    properties (SetAccess = private)
        writeHistory (:, 1) double = double.empty(0, 1);
        readFailureCount (1, 1) double = 0;
    end

    properties (Access = private)
        storedValue (1, 1) double = 0;
    end

    properties
        failNextReads (1, 1) double {mustBeNonnegative, mustBeInteger} = 0;
    end

    methods
        function obj = instrument_rampTrace(address)
            obj@instrumentInterface();
            obj.address = address;
            obj.addChannel("value", 1, setTolerances = 1E-9);
        end

        function clearHistory(obj)
            obj.writeHistory = double.empty(0, 1);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
        end

        function setWriteChannelHelper(obj, ~, setValues)
            obj.storedValue = setValues(1);
            obj.writeHistory(end + 1, 1) = obj.storedValue;
        end

        function getValues = getReadChannelHelper(obj, ~)
            if obj.failNextReads > 0
                obj.failNextReads = obj.failNextReads - 1;
                obj.readFailureCount = obj.readFailureCount + 1;
                error("instrument_rampTrace:TransientReadFailure", "Injected transient read failure.");
            end
            getValues = obj.storedValue;
        end
    end
end
