classdef instrument_toyWorkerRequest < instrumentInterface
    % Toy instrument that requests a dedicated instrument worker.

    properties (Access = private)
        storedValue (1, 1) double = 0
    end

    methods
        function obj = instrument_toyWorkerRequest(address)
            arguments
                address (1, 1) string {mustBeNonzeroLengthText}
            end

            obj@instrumentInterface();
            obj.address = address;
            obj.requireSetCheck = false;
            obj.numWorkersRequired = 1;
            obj.addChannel("value");

            if isempty(getCurrentWorker())
                error("instrument_toyWorkerRequest:NotOnWorker", ...
                    "instrument_toyWorkerRequest must be constructed on the engine worker.");
            end

            requestWorkerSpawn("toyWorkerRequest_worker", @instrument_toyWorkerRequest.workerMain_, 0, obj.address);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No hardware action needed.
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex ~= 1
                error("instrument_toyWorkerRequest:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            experimentContext.print("[toyWorkerRequest engine] set value=%g", setValues(1));
            obj.storedValue = setValues(1);
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex ~= 1
                error("instrument_toyWorkerRequest:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            experimentContext.print("[toyWorkerRequest engine] get value=%g", obj.storedValue);
            getValues = obj.storedValue;
        end
    end

    methods (Static, Access = private)
        function workerMain_(address)
            experimentContext.print("[toyWorkerRequest worker] spawned for %s", address);
        end
    end
end

