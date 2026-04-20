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

            obj.handle_toyWorker = instrumentWorker("toyWorkerRequest_worker", ...
                @instrument_toyWorkerRequest.workerMain_, obj.address);
        end

        function delete(obj)
            if isempty(obj.handle_toyWorker)
                return;
            end
            try
                obj.handle_toyWorker.instSendToInstWorker("STOP");
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
            reply = obj.handle_toyWorker.instQueryInstWorker( ...
                struct("channel", "value", "action", "SET", "value", setValues(1)), obj.workerTimeout);
            if ~(islogical(reply) && isscalar(reply) && reply)
                error("instrument_toyWorkerRequest:InvalidSetReply", ...
                    "Expected logical true reply. Received:\n%s", formattedDisplayText(reply));
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex ~= 1
                error("instrument_toyWorkerRequest:UnsupportedChannel", "Unsupported channel index %d.", channelIndex);
            end
            getValues = double(obj.handle_toyWorker.instQueryInstWorker( ...
                struct("channel", "value", "action", "GET"), obj.workerTimeout));
        end
    end

    methods (Static, Access = private)
        function workerMain_(instWorker, address)
            experimentContext.print("[toyWorkerRequest worker] spawned for %s", address);
            stopCommandIndex = instWorker.instWorkerRegisterStringCommands("STOP");
            valueChannelIndex = instWorker.instWorkerRegisterChannels("value");
            getActionIndex = instWorker.instWorkerActionIndex("GET");
            setActionIndex = instWorker.instWorkerActionIndex("SET");
            stringCommandKindIndex = uint32(1);
            channelCommandKindIndex = uint32(2);
            storedValue = 0;
            keepAlive = true;
            while keepAlive
                try
                    command = instWorker.instWorkerPollFromInst();
                    switch command.kindIndex
                        case stringCommandKindIndex
                            switch command.stringCommandIndex
                                case stopCommandIndex
                                    keepAlive = false;
                                otherwise
                                    error("instrument_toyWorkerRequest:InvalidCommand", ...
                                        "Unsupported worker string command %s.", command.stringCommand);
                            end
                        case channelCommandKindIndex
                            switch command.channelIndex
                                case valueChannelIndex
                                    switch command.actionIndex
                                        case getActionIndex
                                            instWorker.instWorkerSendToInst(storedValue);
                                        case setActionIndex
                                            if ~(isnumeric(command.value) && isscalar(command.value))
                                                error("instrument_toyWorkerRequest:InvalidCommand", ...
                                                    "SET command must include a numeric scalar value.");
                                            end
                                            storedValue = double(command.value);
                                            instWorker.instWorkerSendToInst(true);
                                        otherwise
                                            error("instrument_toyWorkerRequest:InvalidCommand", ...
                                                "Unsupported worker action %s.", command.action);
                                    end
                                otherwise
                                    error("instrument_toyWorkerRequest:InvalidCommand", ...
                                        "Unsupported worker channel %s.", command.channel);
                            end
                        otherwise
                            error("instrument_toyWorkerRequest:InvalidCommand", ...
                                "Unsupported worker command kind %d.", double(command.kindIndex));
                    end
                catch ME
                    instWorker.instWorkerSendExceptionToInst(ME);
                end
            end
        end
    end
end
