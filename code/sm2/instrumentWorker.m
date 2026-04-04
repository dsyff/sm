classdef instrumentWorker < handle
    properties (SetAccess = private)
        instToInstWorkerQueue
        instWorkerToInstQueue
        workerFuture = []
    end

    properties (Access = private)
        requestedBy string
    end

    methods
        function obj = instrumentWorker(requestedBy, workerMainFcn, varargin)
            arguments
                requestedBy {mustBeTextScalar}
                workerMainFcn (1, 1) function_handle
            end
            arguments (Repeating)
                varargin
            end

            assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");

            obj.requestedBy = string(requestedBy);
            obj.instWorkerToInstQueue = parallel.pool.PollableDataQueue;
            obj.workerFuture = requestWorkerSpawn(obj.requestedBy, @instrumentWorker.workerBootstrap_, 0, ...
                obj.instWorkerToInstQueue, obj.requestedBy, workerMainFcn, varargin{:});

            handshakeTimeout = seconds(60);
            startTime = datetime("now");
            while obj.instWorkerToInstQueue.QueueLength == 0
                obj.assertWorkerRunning_();
                assert(datetime("now") - startTime < handshakeTimeout, ...
                    "instrumentWorker:HandshakeTimeout", ...
                    "Instrument worker %s did not complete handshake in time.", obj.requestedBy);
                pause(1E-6);
            end

            reply = poll(obj.instWorkerToInstQueue);
            if isa(reply, "MException")
                rethrow(reply);
            end
            if ~isa(reply, "parallel.pool.PollableDataQueue")
                error("instrumentWorker:InvalidHandshake", ...
                    "Instrument worker %s returned an invalid handshake payload:\n%s", ...
                    obj.requestedBy, formattedDisplayText(reply));
            end
            obj.instToInstWorkerQueue = reply;
        end

        function instSendToInstWorker(obj, command)
            arguments
                obj (1, 1) instrumentWorker
                command
            end

            obj.instFlushFromInstWorker();
            obj.assertWorkerRunning_();
            send(obj.instToInstWorkerQueue, command);
        end

        function reply = instQueryInstWorker(obj, command, timeout)
            arguments
                obj (1, 1) instrumentWorker
                command
                timeout duration = seconds(5)
            end

            obj.instFlushFromInstWorker();
            obj.assertWorkerRunning_();
            send(obj.instToInstWorkerQueue, command);
            reply = obj.instPollFromInstWorker(timeout);
        end

        function reply = instPollFromInstWorker(obj, timeout)
            arguments
                obj (1, 1) instrumentWorker
                timeout duration = seconds(5)
            end

            startTime = datetime("now");
            while obj.instWorkerToInstQueue.QueueLength == 0
                obj.assertWorkerRunning_();
                assert(datetime("now") - startTime < timeout, ...
                    "instrumentWorker:Timeout", ...
                    "Instrument worker %s did not respond in time.", obj.requestedBy);
                pause(1E-6);
            end

            reply = poll(obj.instWorkerToInstQueue);
            obj.validateReply_(reply);
        end

        function instFlushFromInstWorker(obj)
            arguments
                obj (1, 1) instrumentWorker
            end

            while obj.instWorkerToInstQueue.QueueLength > 0
                reply = poll(obj.instWorkerToInstQueue);
                obj.validateReply_(reply);
                error("instrumentWorker:UnexpectedReply", ...
                    "Unexpected queued reply from instrument worker %s:\n%s", ...
                    obj.requestedBy, formattedDisplayText(reply));
            end
        end
    end

    methods (Static)
        function workerBootstrap_(instWorkerToInstQueue, requestedBy, workerMainFcn, varargin)
            arguments
                instWorkerToInstQueue (1, 1) parallel.pool.PollableDataQueue
                requestedBy {mustBeTextScalar}
                workerMainFcn (1, 1) function_handle
            end
            arguments (Repeating)
                varargin
            end

            try
                instWorker = instrumentWorkerRuntime(instWorkerToInstQueue, requestedBy);
                workerMainFcn(instWorker, varargin{:});
            catch ME
                try
                    send(instWorkerToInstQueue, ME);
                catch
                end
                rethrow(ME);
            end
        end
    end

    methods (Access = private)
        function assertWorkerRunning_(obj)
            if isempty(obj.workerFuture)
                return;
            end
            if matches(string(obj.workerFuture.State), "running")
                return;
            end
            if isprop(obj.workerFuture, "Error") && ~isempty(obj.workerFuture.Error)
                if isprop(obj.workerFuture.Error, "remotecause")
                    rethrow(obj.workerFuture.Error.remotecause{1});
                end
                rethrow(obj.workerFuture.Error);
            end
            error("instrumentWorker:Stopped", "Instrument worker %s is not running.", obj.requestedBy);
        end

        function validateReply_(obj, reply)
            if isempty(reply)
                error("instrumentWorker:EmptyReply", ...
                    "Empty reply received from instrument worker %s.", obj.requestedBy);
            end
            if isa(reply, "MException")
                rethrow(reply);
            end
            if isstring(reply) && startsWith(reply, "Error", "IgnoreCase", true)
                error(reply);
            end
        end
    end
end
