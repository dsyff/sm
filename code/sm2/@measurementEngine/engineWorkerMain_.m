function engineWorkerMain_(engineToClient, recipe, workerFprintfQueue, experimentRootPath, options)
    % Worker process entrypoint: build rack, then serve requests.
    %
    % Notes:
    % - This function must not touch any GUI.
    % - It uses PollableDataQueue only (no Destination).
    arguments
        engineToClient parallel.pool.PollableDataQueue
        recipe (1, 1) instrumentRackRecipe
        workerFprintfQueue (1, 1) parallel.pool.DataQueue
        experimentRootPath (1, 1) string = ""
        options.verbose (1, 1) logical = false
        options.logFile (1, 1) string = ""
    end

    % Mirror experiment root on the engine worker (available to all worker-side code).
    if strlength(experimentRootPath) == 0
        experimentRootPath = string(getenv("SM_EXPERIMENT_ROOT"));
    end
    if strlength(experimentRootPath) == 0
        experimentRootPath = string(pwd);
    end
    experimentContext.setExperimentRootPath(experimentRootPath);
    experimentContext.setFprintfRelay(workerFprintfQueue, "engine");

    verbose = options.verbose;
    logFile = options.logFile;
    fid = -1;
    if verbose
        if strlength(logFile) == 0
            error("measurementEngine:WorkerLogMissingFile", "Worker verbose logging requires logFile.");
        end
        [fid, msg] = fopen(char(logFile), "a");
        if fid < 0
            error("measurementEngine:WorkerLogOpenFailed", "Failed to open worker log file. %s", msg);
        end
        cleaner = onCleanup(@() fclose(fid));
    end

    function wlog(msg)
        if ~verbose || fid < 0
            return;
        end
        try
            ts = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
            experimentContext.print(fid, "%s %s\n", ts, char(msg));
            fflush(fid);
        catch
        end
    end

    keepAlive = true;
    clientToEngine = parallel.pool.PollableDataQueue;

    if verbose
        wlog("engine worker starting. logFile=" + logFile);
    end
    send(engineToClient, struct("type", "engineReady", "clientToEngine", clientToEngine));

    try
        % Provide a generic "spawn on client" API for worker-side code.
        % Instruments that need additional workers can call requestWorkerSpawn(...).
        rack = measurementEngine.buildRackFromRecipe_(recipe, @spawnOnClient);

        % Publish channel metadata back to client.
        if verbose
            wlog("rackReady channels=" + height(rack.channelTable));
        end
        send(engineToClient, struct( ...
            "type", "rackReady", ...
            "channelFriendlyNames", rack.channelTable.channelFriendlyNames(:), ...
            "channelSizes", double(rack.channelTable.channelSizes(:))));

    catch ME
        if verbose
            wlog("rackReady failed: " + ME.identifier + " " + ME.message);
        end
        send(engineToClient, struct("type", "rackReady", "channelFriendlyNames", string.empty(0, 1), "channelSizes", double.empty(0, 1), "ok", false, "error", measurementEngine.serializeException_(ME)));
        return;
    end

    % Serve basic requests.
    while keepAlive
        if clientToEngine.QueueLength == 0
            pause(1E-6);
            continue;
        end

        msg = poll(clientToEngine);
        if ~isstruct(msg) || ~isfield(msg, "type")
            continue;
        end

        switch msg.type
            case "shutdown"
                if verbose
                    wlog("recv shutdown");
                end
                keepAlive = false;

            case "run"
                currentRunRequestId = msg.requestId;
                currentRunScanObj = msg.scan;
                if verbose
                    wlog("recv run " + currentRunRequestId + " mode=" + currentRunScanObj.mode + " name=" + currentRunScanObj.name);
                end
                ok = true;
                err = [];
                data = {};
                completed = false;
                try
                    if ~isa(currentRunScanObj, "measurementScan")
                        error("measurementEngine:InvalidScan", "run expects a measurementScan.");
                    end

                    mode = currentRunScanObj.mode;
                    logCore = [];
                    if verbose
                        logCore = @wlog;
                    end
                    if mode == "safe"
                        [data, stopped] = measurementEngine.runSafeScanCore_(rack, currentRunScanObj, clientToEngine, engineToClient, currentRunRequestId, logCore);
                        completed = ~stopped;
                    elseif mode == "turbo"
                        snapshotInterval = seconds(0.2);
                        if isfield(msg, "snapshotInterval") && ~isempty(msg.snapshotInterval)
                            snapshotInterval = msg.snapshotInterval;
                            if ~isduration(snapshotInterval)
                                snapshotInterval = seconds(double(snapshotInterval));
                            end
                        end
                        if ~(isduration(snapshotInterval) && isfinite(seconds(snapshotInterval)) && snapshotInterval > seconds(0))
                            error("measurementEngine:InvalidTurboInterval", "Invalid snapshotInterval for turbo mode.");
                        end
                        [data, ~, stopped] = measurementEngine.runTurboScanCore_(rack, currentRunScanObj, clientToEngine, engineToClient, currentRunRequestId, snapshotInterval, logCore);
                        completed = ~stopped;
                    else
                        error("measurementEngine:InvalidMode", "Unknown scan mode %s.", mode);
                    end

                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                end

                send(engineToClient, struct( ...
                    "type", "runDone", ...
                    "requestId", currentRunRequestId, ...
                    "ok", ok, ...
                    "completed", completed, ...
                    "data", {data}, ...
                    "error", err));
                if verbose
                    wlog("send runDone " + currentRunRequestId + " ok=" + ok);
                end

            case "eval"
                requestId = msg.requestId;
                if verbose
                    wlog("recv eval " + requestId);
                end
                ok = true;
                err = [];
                out = [];
                try
                    nOut = 0;
                    if isfield(msg, "nOut") && ~isempty(msg.nOut)
                        nOut = double(msg.nOut);
                    end
                    if ~(isscalar(nOut) && isfinite(nOut) && nOut >= 0 && mod(nOut, 1) == 0)
                        error("measurementEngine:InvalidEvalNOut", "nOut must be a nonnegative integer.");
                    end
                    if nOut > 0
                        out = evalin("base", char(msg.code));
                    else
                        evalin("base", char(msg.code));
                    end
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                    out = [];
                end
                reply = struct();
                reply.type = "evalDone";
                reply.requestId = requestId;
                reply.ok = ok;
                reply.output = out;
                reply.error = err;
                send(engineToClient, reply);

            case "rackDisp"
                requestId = msg.requestId;
                if verbose
                    wlog("recv rackDisp " + requestId);
                end
                ok = true;
                err = [];
                text = "";
                try
                    text = string(formattedDisplayText(rack));
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                end
                send(engineToClient, struct("type", "rackDispDone", "requestId", requestId, "ok", ok, "text", text, "error", err));

            case "rackEditInfo"
                requestId = msg.requestId;
                if verbose
                    wlog("recv rackEditInfo " + requestId);
                end
                ok = true;
                err = [];
                info = table( ...
                    Size = [0, 7], ...
                    VariableTypes = ["string", "string", "double", "cell", "cell", "cell", "cell"], ...
                    VariableNames = ["instrumentFriendlyName", "channelFriendlyName", "channelSize", "rampRates", "rampThresholds", "softwareMins", "softwareMaxs"]);
                try
                    info = rack.getRackInfoForEditing();
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                end
                send(engineToClient, struct("type", "rackEditInfoDone", "requestId", requestId, "ok", ok, "info", info, "error", err));

            case "rackEditPatch"
                requestId = msg.requestId;
                if verbose
                    wlog("recv rackEditPatch " + requestId);
                end
                ok = true;
                err = [];
                try
                    if isfield(msg, "patch") && isa(msg.patch, "instrumentRackEditPatch")
                        experimentContext.print("rackEditPatch received (%s): %d row(s).", requestId, msg.patch.numEntries());
                    else
                        payloadClass = "missing";
                        if isfield(msg, "patch")
                            payloadClass = class(msg.patch);
                        end
                        experimentContext.print("rackEditPatch received invalid payload (%s): %s.", requestId, payloadClass);
                    end
                    if ~isfield(msg, "patch") || ~isa(msg.patch, "instrumentRackEditPatch")
                        error("measurementEngine:InvalidRackEditPatch", ...
                            "rackEditPatch expects a scalar instrumentRackEditPatch payload.");
                    end
                    rack.applyRackEditPatch(msg.patch);
                    experimentContext.print("rackEditPatch applied (%s).", requestId);
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                    experimentContext.print("rackEditPatch failed (%s): %s", requestId, ME.message);
                end
                send(engineToClient, struct("type", "rackEditPatchDone", "requestId", requestId, "ok", ok, "error", err));

            case "rackGet"
                requestId = msg.requestId;
                if verbose
                    wlog("recv rackGet " + requestId);
                end
                ok = true;
                err = [];
                values = [];
                try
                    values = rack.rackGet(string(msg.channelNames));
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                end
                send(engineToClient, struct("type", "rackGetDone", "requestId", requestId, "ok", ok, "values", values, "error", err));

            case "rackSet"
                requestId = msg.requestId;
                if verbose
                    wlog("recv rackSet " + requestId);
                end
                ok = true;
                err = [];
                try
                    rack.rackSet(string(msg.channelNames), double(msg.values));
                catch ME
                    ok = false;
                    err = measurementEngine.serializeException_(ME);
                end
                send(engineToClient, struct("type", "rackSetDone", "requestId", requestId, "ok", ok, "error", err));

            otherwise
                % ignore unknown
        end
    end

    function spawnOnClient(requestedBy, fcn, nOut, varargin)
        if nargin < 1 || strlength(string(requestedBy)) == 0
            requestedBy = string(func2str(fcn));
        else
            requestedBy = string(requestedBy);
        end
        if verbose
            wlog("spawnOnClient " + requestedBy + " -> " + func2str(fcn));
        end

        requestId = string(java.util.UUID.randomUUID());
        send(engineToClient, struct( ...
            "type", "parfeval", ...
            "requestId", requestId, ...
            "requestedBy", string(requestedBy), ...
            "fcn", fcn, ...
            "nOut", nOut, ...
            "args", {varargin}));

        startTime = datetime("now");
        timeout = minutes(2);
        while true
            if clientToEngine.QueueLength > 0
                msg2 = poll(clientToEngine);
                if isstruct(msg2) && isfield(msg2, "type")
                    msgType2 = msg2.type;
                    if msgType2 == "shutdown"
                        error("measurementEngine:ParfevalCancelled", "Engine worker is shutting down.");
                    end
                    if msgType2 == "parfevalDone" && isfield(msg2, "requestId") && msg2.requestId == requestId
                        if isfield(msg2, "ok") && ~logical(msg2.ok)
                            error("measurementEngine:ParfevalFailed", "%s", msg2.error.message);
                        end
                        if isfield(msg2, "state") && msg2.state == "queued"
                            error("measurementEngine:ParfevalQueued", ...
                                "Worker spawn request was queued. Increase numeWorkersRequested in the recipe (pool size) and restart the engine.");
                        end
                        return;
                    end
                end
            end
            assert(datetime("now") - startTime < timeout, "measurementEngine:ParfevalTimeout", "Timed out waiting for parfevalDone.");
            pause(1E-6);
        end
    end

end

