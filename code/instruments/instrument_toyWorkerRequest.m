classdef instrument_toyWorkerRequest < instrumentInterface
    % Toy instrument that requests a dedicated instrument worker.

    properties (Access = private)
        handle_toyWorker
        workerTimeout duration = seconds(5)
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

            obj.handle_toyWorker = requestInstrumentWorker("toyWorkerRequest_worker", ...
                @instrument_toyWorkerRequest.workerMain_, obj.address);
        end

        function delete(obj)
            if isempty(obj.handle_toyWorker)
                return;
            end
            try
                instrument_toyWorkerRequest.workerSend_(obj.handle_toyWorker, "STOP");
            catch
            end
            obj.handle_toyWorker = [];
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
            reply = instrument_toyWorkerRequest.workerQuery_(obj.handle_toyWorker, ...
                struct("action", "SET", "value", setValues(1)), obj.workerTimeout);
            if ~(islogical(reply) && isscalar(reply) && reply)
                error("instrument_toyWorkerRequest:InvalidSetReply", ...
                    "Expected logical true reply. Received:\n%s", formattedDisplayText(reply));
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex ~= 1
                error("instrument_toyWorkerRequest:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            getValues = double(instrument_toyWorkerRequest.workerQuery_( ...
                obj.handle_toyWorker, struct("action", "GET"), obj.workerTimeout));
        end
    end

    methods (Static, Access = private)
        function workerMain_(workerToInstrument, address)
            instrumentToWorker = parallel.pool.PollableDataQueue;
            send(workerToInstrument, instrumentToWorker);
            experimentContext.print("[toyWorkerRequest worker] spawned for %s", address);
            storedValue = 0;
            keepAlive = true;
            while keepAlive
                if instrumentToWorker.QueueLength == 0
                    pause(1E-6);
                    continue;
                end
                command = poll(instrumentToWorker);
                try
                    if isstruct(command)
                        if ~isfield(command, "action")
                            error("instrument_toyWorkerRequest:InvalidCommand", ...
                                "Worker command struct must include action.");
                        end
                        switch string(command.action)
                            case "GET"
                                send(workerToInstrument, storedValue);
                            case "SET"
                                if ~(isfield(command, "value") && isnumeric(command.value) && isscalar(command.value))
                                    error("instrument_toyWorkerRequest:InvalidCommand", ...
                                        "SET command must include a numeric scalar value.");
                                end
                                storedValue = double(command.value);
                                send(workerToInstrument, true);
                            otherwise
                                error("instrument_toyWorkerRequest:InvalidCommand", ...
                                    "Unsupported worker action %s.", string(command.action));
                        end
                    elseif (isstring(command) && isscalar(command)) || ischar(command)
                        switch string(command)
                            case "STOP"
                                keepAlive = false;
                            otherwise
                                error("instrument_toyWorkerRequest:InvalidCommand", ...
                                    "Unsupported worker string command %s.", string(command));
                        end
                    else
                        error("instrument_toyWorkerRequest:InvalidCommand", ...
                            "Worker command must be a struct or string.");
                    end
                catch ME
                    send(workerToInstrument, ME);
                end
            end
        end

        function reply = workerQuery_(handle_toyWorker, command, timeout)
            instrument_toyWorkerRequest.workerFlush_(handle_toyWorker);
            send(handle_toyWorker.instrumentToWorker, command);
            startTime = datetime("now");
            while handle_toyWorker.workerToInstrument.QueueLength == 0
                assert(datetime("now") - startTime < timeout, ...
                    "instrument_toyWorkerRequest:WorkerTimeout", ...
                    "Toy worker did not respond in time.");
                pause(1E-6);
            end
            reply = poll(handle_toyWorker.workerToInstrument);
            if isempty(reply)
                error("instrument_toyWorkerRequest:EmptyReply", "Empty reply received from toy worker.");
            end
            if isa(reply, "MException")
                rethrow(reply);
            end
        end

        function workerSend_(handle_toyWorker, command)
            instrument_toyWorkerRequest.workerFlush_(handle_toyWorker);
            send(handle_toyWorker.instrumentToWorker, command);
        end

        function workerFlush_(handle_toyWorker)
            while handle_toyWorker.workerToInstrument.QueueLength > 0
                reply = poll(handle_toyWorker.workerToInstrument);
                if isempty(reply)
                    error("instrument_toyWorkerRequest:EmptyReply", "Empty reply received from toy worker.");
                end
                if isa(reply, "MException")
                    rethrow(reply);
                end
                error("instrument_toyWorkerRequest:UnexpectedReply", ...
                    "Unexpected queued worker reply:\n%s", formattedDisplayText(reply));
            end
        end
    end
end
