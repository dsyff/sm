function handle_instrumentWorker = requestInstrumentWorker(requestedBy, workerFcn, varargin)
%REQUESTINSTRUMENTWORKER Spawn an instrument-owned worker and complete its initial queue handshake.
%
% Contract:
% - workerFcn is spawned via requestWorkerSpawn(requestedBy, ...)
% - workerFcn must accept workerToInstrument as its first input
% - workerFcn must send instrumentToWorker back as its first reply

arguments
    requestedBy {mustBeTextScalar}
    workerFcn (1, 1) function_handle
end
arguments (Repeating)
    varargin
end

assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");

workerToInstrument = parallel.pool.PollableDataQueue;
requestWorkerSpawn(requestedBy, workerFcn, 0, workerToInstrument, varargin{:});

handshakeTimeout = seconds(60);
startTime = datetime("now");
while workerToInstrument.QueueLength == 0
    assert(datetime("now") - startTime < handshakeTimeout, ...
        "requestInstrumentWorker:HandshakeTimeout", ...
        "Instrument worker %s did not complete handshake in time.", string(requestedBy));
    pause(1E-6);
end

instrumentToWorker = poll(workerToInstrument);
if ~isa(instrumentToWorker, "parallel.pool.PollableDataQueue")
    if isa(instrumentToWorker, "MException")
        rethrow(instrumentToWorker);
    end
    error("requestInstrumentWorker:InvalidHandshake", ...
        "Instrument worker %s returned an invalid handshake payload:\n%s", ...
        string(requestedBy), formattedDisplayText(instrumentToWorker));
end

handle_instrumentWorker = struct( ...
    "instrumentToWorker", instrumentToWorker, ...
    "workerToInstrument", workerToInstrument);
end
