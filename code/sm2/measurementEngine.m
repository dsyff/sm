classdef measurementEngine < handle
    % measurementEngine
    % Client-side orchestrator for measurements and GUIs.
    %
    % Construction modes:
    % - measurementEngine(recipe): rack is built on an engine worker; measurement runs on that worker.
    % - measurementEngine(recipe, singleThreaded=true): recipe is materialized on the client; measurement runs locally.
    % - measurementEngine.fromRack(rack): rack lives on the client; measurement runs locally (single-threaded).

    properties
        turboSnapshotInterval (1, 1) duration = seconds(0.2)
        verboseClient (1, 1) logical = false
    end

    properties (SetAccess = private)
        % "rack" (local) or "recipe" (worker rack)
        constructionMode (1, 1) string {mustBeMember(constructionMode, ["rack", "recipe"])} = "rack"

        experimentRootPath (1, 1) string = ""

        rackLocal instrumentRack = instrumentRack.empty(0, 1)
        recipe instrumentRackRecipe = instrumentRackRecipe.empty(0, 1)

        pool = []

        % Worker engine (recipe mode only)
        clientToEngine parallel.pool.PollableDataQueue = parallel.pool.PollableDataQueue.empty(0, 1)
        engineToClient parallel.pool.PollableDataQueue = parallel.pool.PollableDataQueue.empty(0, 1)

        verboseWorker (1, 1) logical = false
        workerLogFile (1, 1) string = ""
        clientLogFile (1, 1) string = ""

        % Channel metadata (recipe mode)
        channelFriendlyNames (:, 1) string = string.empty(0, 1)
        channelSizes (:, 1) double = double.empty(0, 1)

        % Spawned futures on the client (instrument workers, etc.)
        spawnedFutures (1, :) struct = struct( ...
            "future", {}, ...
            "requestedBy", {}, ...
            "fcn", {}, ...
            "args", {}, ...
            "time", {})
    end

    properties (Dependent, SetAccess = private)
        % Array of structs with fields:
        % - future: parallel.FevalFuture
        % - purpose: "engine" or instrument friendly name
        workerFutures (1, :) struct
    end

    properties (Access = private)
        engineToClientBacklog (1, :) cell = cell(1, 0)
        workerFprintfQueue = parallel.pool.DataQueue.empty(0, 1)
        workerFprintfListener = []
    end

    methods (Static)
        function obj = fromRack(rack, options)
            arguments
                rack (1, 1) instrumentRack
                options.verboseClient (1, 1) logical = false
                options.clientLogFile (1, 1) string = ""
                options.experimentRootPath (1, 1) string = ""
            end

            obj = measurementEngine(instrumentRackRecipe(), ...
                internalDeferInit = true, ...
                verboseClient = options.verboseClient, ...
                clientLogFile = options.clientLogFile, ...
                experimentRootPath = options.experimentRootPath);
            obj.constructionMode = "rack";
            obj.rackLocal = rack;
            obj.recipe = instrumentRackRecipe.empty(0, 1);
            obj.ensurePoolForLocalRack_();
            obj.rackLocal.flush();
        end
    end

    methods
        function obj = measurementEngine(recipe, options)
            arguments
                recipe (1, 1) instrumentRackRecipe
                options.internalDeferInit (1, 1) logical = false
                options.singleThreaded (1, 1) logical = false
                options.verboseClient (1, 1) logical = false
                options.verboseWorker (1, 1) logical = false
                options.workerLogFile (1, 1) string = ""
                options.clientLogFile (1, 1) string = ""
                options.experimentRootPath (1, 1) string = ""
            end

            rootPath = options.experimentRootPath;
            if strlength(rootPath) == 0
                rootPath = string(getenv("SM_EXPERIMENT_ROOT"));
            end
            if strlength(rootPath) == 0
                rootPath = string(pwd);
            end
            obj.experimentRootPath = rootPath;
            experimentContext.setExperimentRootPath(rootPath);

            obj.verboseClient = options.verboseClient;
            obj.verboseWorker = options.verboseWorker;
            obj.workerLogFile = options.workerLogFile;
            obj.clientLogFile = options.clientLogFile;

            if obj.verboseClient && strlength(obj.clientLogFile) == 0
                obj.clientLogFile = measurementEngine.makeDefaultLogFile_("client");
            end
            if obj.verboseClient
                obj.logClient_("client verbose enabled: " + obj.clientLogFile);
            end

            if options.internalDeferInit
                return;
            end

            if options.singleThreaded
                obj.constructionMode = "rack";
                obj.rackLocal = measurementEngine.buildRackFromRecipe_(recipe);
                obj.recipe = instrumentRackRecipe.empty(0, 1);
                obj.ensurePoolForLocalRack_();
                return;
            end

            obj.constructionMode = "recipe";
            obj.recipe = recipe;
            obj.ensurePoolForRecipe_();
            obj.startEngineWorker_();
        end

        function delete(obj)
            try
                if obj.constructionMode == "recipe"
                    obj.safeSendToEngine_(struct("type", "shutdown"));
                end
            catch
            end

            try
                fut = obj.engineWorkerFuture_();
                if ~isempty(fut)
                    cancel(fut);
                end
            catch
            end

            try
                obj.workerFprintfListener = [];
                obj.workerFprintfQueue = parallel.pool.DataQueue.empty(0, 1);
            catch
            end

            try
                if ~isempty(obj.pool) && isvalid(obj.pool)
                    delete(obj.pool);
                end
            catch
            end
        end

        function fut = parfevalOnClient(obj, fcn, nOut, varargin)
            arguments
                obj
                fcn (1, 1) function_handle
                nOut (1, 1) double {mustBeNonnegative, mustBeInteger}
            end
            arguments (Repeating)
                varargin
            end

            if isempty(obj.pool) || ~isvalid(obj.pool)
                error("measurementEngine:NoPool", "No parallel pool available for parfevalOnClient.");
            end

            fut = parfeval(obj.pool, fcn, nOut, varargin{:});

            st = dbstack("-completenames");
            requestedBy = "unknown";
            if numel(st) >= 2
                requestedBy = string(st(2).name);
            end

            entry = struct();
            entry.future = fut;
            entry.requestedBy = requestedBy;
            entry.fcn = fcn;
            entry.args = {varargin};
            entry.time = datetime("now");
            obj.spawnedFutures(end+1) = entry;

            obj.logClient_("parfevalOnClient: " + requestedBy + " -> " + func2str(fcn));
        end

        function workers = get.workerFutures(obj)
            workers = struct("future", {}, "purpose", {});
            for k = 1:numel(obj.spawnedFutures)
                workers(end+1) = struct( ...
                    "future", obj.spawnedFutures(k).future, ...
                    "purpose", obj.spawnedFutures(k).requestedBy);
            end
        end

        function values = rackGet(obj, channelNames)
            arguments
                obj
                channelNames string {mustBeNonzeroLengthText, mustBeVector}
            end

            channelNames = channelNames(:);
            if obj.constructionMode == "rack"
                values = obj.rackLocal.rackGet(channelNames);
                values = values(:);
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "rackGet", ...
                "requestId", requestId, ...
                "channelNames", channelNames));

            reply = obj.waitForEngineReply_(requestId, "rackGetDone");
            if isfield(reply, "ok") && ~reply.ok
                obj.throwRemoteError_(reply);
            end
            values = reply.values(:);
        end

        function rackSet(obj, channelNames, values)
            arguments
                obj
                channelNames string {mustBeNonzeroLengthText, mustBeVector}
                values double {mustBeVector}
            end

            channelNames = channelNames(:);
            values = values(:);

            if obj.constructionMode == "rack"
                obj.rackLocal.rackSet(channelNames, values);
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "rackSet", ...
                "requestId", requestId, ...
                "channelNames", channelNames, ...
                "values", values));

            reply = obj.waitForEngineReply_(requestId, "rackSetDone");
            if isfield(reply, "ok") && ~reply.ok
                obj.throwRemoteError_(reply);
            end
        end

        function out = evalOnEngine(obj, codeString)
            arguments
                obj
                codeString (1, 1) string {mustBeNonzeroLengthText}
            end

            out = [];
            if obj.constructionMode == "rack"
                if nargout == 0
                    evalin("base", char(codeString));
                else
                    out = evalin("base", char(codeString));
                end
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "eval", ...
                "requestId", requestId, ...
                "code", codeString, ...
                "nOut", nargout));

            reply = obj.waitForEngineReply_(requestId, "evalDone");
            if isfield(reply, "ok") && ~reply.ok
                obj.throwRemoteError_(reply);
            end
            if nargout > 0 && isfield(reply, "output")
                out = reply.output;
            end
        end

        function txt = rackDisplayString(obj)
            if obj.constructionMode == "rack"
                rack = obj.rackLocal;
                txt = formattedDisplayText(rack);
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "rackDisp", ...
                "requestId", requestId));

            reply = obj.waitForEngineReply_(requestId, "rackDispDone");
            if isfield(reply, "ok") && ~logical(reply.ok)
                obj.throwRemoteError_(reply);
            end
            txt = reply.text;
        end

        function printRack(obj)
            txt = obj.rackDisplayString();
            experimentContext.print("Main rack starts.");
            experimentContext.print(txt);
            experimentContext.print("Main rack ends.");
        end

        function [channelNames, channelSizes] = getChannelMetadata(obj)
            channelNames = obj.channelFriendlyNames;
            channelSizes = obj.channelSizes;
            if obj.constructionMode == "rack"
                channelNames = obj.rackLocal.channelTable.channelFriendlyNames(:);
                channelSizes = double(obj.rackLocal.channelTable.channelSizes(:));
            end
        end

        function dataOut = run(obj, scan, filename, mode)
            arguments
                obj
                scan
                filename (1, 1) string = ""
                mode (1, 1) string {mustBeMember(mode, ["safe", "turbo"])} = "safe"
            end

            scanObj = scan;
            if isstruct(scanObj)
                scanObj = measurementScan.fromLegacy(scanObj, @(name) obj.channelSizeOf_(name), mode);
            elseif isa(scanObj, "measurementScan")
                % ok
            else
                error("measurementEngine:InvalidScan", "scan must be a struct or measurementScan.");
            end

            obj.logClient_("run() entered mode=" + mode + " name=" + scanObj.name + " loops=" + numel(scanObj.loops));
            autoRun = false;
            runToUse = NaN;
            if strlength(filename) == 0
                dataDir = "";
                try
                    dataDir = string(smdatapathGetState());
                catch
                end
                if strlength(dataDir) == 0
                    dataDir = string(smdatapathDefaultPath());
                    try
                        smdatapathUpdateGlobalState("engine", dataDir);
                    catch
                    end
                end
                if ~exist(dataDir, "dir")
                    mkdir(dataDir);
                end

                baseName = scanObj.name;
                if strlength(baseName) == 0
                    baseName = "scan";
                end
                baseName = regexprep(baseName, "[\\/:*?""<>|.]", "_");

                runCandidate = NaN;
                try
                    runCandidate = smrunGetState();
                catch
                end
                if ~(isfinite(runCandidate) && ~isnan(runCandidate))
                    runCandidate = 0;
                end
                runToUse = smrunNextAvailableRunNumber(char(dataDir), runCandidate);
                runstring = sprintf('%03u', runToUse);
                filename = fullfile(dataDir, runstring + "_" + baseName + ".mat");
                autoRun = true;
            end

            obj.logClient_("run() target file=" + filename);

            if obj.constructionMode == "rack"
                dataOut = obj.runLocal_(scanObj, filename);
            else
                dataOut = obj.runOnWorker_(scanObj, filename, mode);
            end

            if autoRun
                try
                    smrunUpdateGlobalState("engine", smrunIncrement(runToUse));
                catch
                end
            end
        end
    end

    methods (Access = private)
        function logClient_(obj, msg)
            if ~obj.verboseClient
                return;
            end
            try
                if strlength(obj.clientLogFile) == 0
                    obj.clientLogFile = measurementEngine.makeDefaultLogFile_("client");
                end
                [fid, openMsg] = fopen(char(obj.clientLogFile), "a");
                if fid < 0
                    error("measurementEngine:ClientLogOpenFailed", "Failed to open client log file. %s", openMsg);
                end
                c = onCleanup(@() fclose(fid));
                ts = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss.SSS"));
                experimentContext.print(fid, "%s measurementEngine: %s\n", ts, char(msg));
            catch
            end
        end

        function onWorkerFprintf_(~, payload)
            if ~isstruct(payload) || ~isfield(payload, "message")
                return;
            end

            header = "worker";
            if isfield(payload, "header") && ~isempty(payload.header)
                header = string(payload.header);
            end

            msg = string(payload.message);
            if strlength(msg) == 0
                return;
            end

            lines = splitlines(msg);
            if numel(lines) > 1 && strlength(lines(end)) == 0
                lines = lines(1:end-1);
            end

            for i = 1:numel(lines)
                experimentContext.print("%s: %s", header, lines(i));
            end
        end

        function fut = engineWorkerFuture_(obj)
            fut = [];
            if isempty(obj.spawnedFutures)
                return;
            end
            requestedBy = string({obj.spawnedFutures.requestedBy});
            idx = find(requestedBy == "engine", 1, "first");
            if ~isempty(idx)
                fut = obj.spawnedFutures(idx).future;
            end
        end

        function ensurePoolForLocalRack_(obj)
            nInstrumentWorkers = 0;
            if ~isempty(obj.rackLocal) && ~isempty(obj.rackLocal.instrumentTable)
                instruments = obj.rackLocal.instrumentTable.instruments;
                for k = 1:numel(instruments)
                    try
                        nInstrumentWorkers = nInstrumentWorkers + double(instruments(k).numWorkersRequired);
                    catch
                    end
                end
            end
            if nInstrumentWorkers <= 0
                obj.pool = gcp("nocreate");
                return;
            end

            obj.recreatePool_(nInstrumentWorkers);
        end

        function ensurePoolForRecipe_(obj)
            nInstrumentWorkers = obj.recipe.totalWorkersRequired();
            n = 1 + nInstrumentWorkers; % engine worker + instrument workers
            obj.recreatePool_(n);
        end

        function recreatePool_(obj, n)
            arguments
                obj
                n (1, 1) double {mustBePositive, mustBeInteger}
            end

            currentPool = gcp("nocreate");
            if ~isempty(currentPool)
                delete(currentPool);
            end
            obj.pool = parpool("Processes", n);
        end

        function startEngineWorker_(obj)
            obj.engineToClient = parallel.pool.PollableDataQueue;
            obj.clientToEngine = parallel.pool.PollableDataQueue.empty(0, 1);
            obj.workerFprintfListener = [];
            obj.workerFprintfQueue = parallel.pool.DataQueue;
            obj.workerFprintfListener = afterEach(obj.workerFprintfQueue, @(payload) obj.onWorkerFprintf_(payload));

            workerVerbose = obj.verboseWorker;
            logFile = obj.workerLogFile;
            if workerVerbose && strlength(logFile) == 0
                logFile = measurementEngine.makeDefaultLogFile_("engine");
                obj.workerLogFile = logFile;
            end
            if workerVerbose
                obj.logClient_("worker verbose enabled: " + logFile);
            end

            obj.parfevalOnClient(@measurementEngine.engineWorkerMain_, 0, obj.engineToClient, obj.recipe, obj.workerFprintfQueue, obj.experimentRootPath, ...
                verbose = workerVerbose, logFile = logFile);
            if ~isempty(obj.spawnedFutures)
                obj.spawnedFutures(end).requestedBy = "engine";
            end

            % Wait for engineReady + rackReady (and service parfeval requests during startup).
            startTime = datetime("now");
            timeout = minutes(5);
            gotEngineReady = false;
            while true
                if obj.engineToClient.QueueLength > 0
                    msg = poll(obj.engineToClient);
                    if isstruct(msg) && isfield(msg, "type")
                        msgType = msg.type;
                        if msgType == "engineReady"
                            if isfield(msg, "clientToEngine") && isa(msg.clientToEngine, "parallel.pool.PollableDataQueue")
                                obj.clientToEngine = msg.clientToEngine;
                                gotEngineReady = true;
                                continue;
                            end
                            error("measurementEngine:EngineProtocolError", "engineReady did not include clientToEngine queue.");
                        end
                        if msgType == "rackReady"
                            if isfield(msg, "ok") && ~logical(msg.ok)
                                if isfield(msg, "error") && ~isempty(msg.error) && isfield(msg.error, "message")
                                    error("measurementEngine:EngineRackBuildFailed", "%s", msg.error.message);
                                end
                                error("measurementEngine:EngineRackBuildFailed", "Engine worker failed to build rack.");
                            end
                            obj.channelFriendlyNames = msg.channelFriendlyNames(:);
                            obj.channelSizes = msg.channelSizes(:);
                            break;
                        end
                    end

                    if isstruct(msg) && isfield(msg, "type") && msg.type == "parfeval" && ~gotEngineReady
                        error("measurementEngine:EngineProtocolError", "Received parfeval before engineReady; cannot respond.");
                    end
                    obj.handleEngineToClientMessage_(msg);
                end

                fut = obj.engineWorkerFuture_();
                if ~isempty(fut) && isprop(fut, "State") && fut.State ~= "running"
                    if isprop(fut, "Error") && ~isempty(fut.Error)
                        throw(fut.Error);
                    end
                    error("measurementEngine:EngineWorkerFailed", "Engine worker failed to start. State: %s", fut.State);
                end

                assert(datetime("now") - startTime < timeout, "measurementEngine:EngineWorkerTimeout", "Timed out waiting for engine worker rackReady.");
                pause(0.001);
            end
        end

        function handleEngineToClientMessage_(obj, msg)
            if ~isstruct(msg) || ~isfield(msg, "type")
                return;
            end

            switch msg.type
                case "parfeval"
                    obj.handleParfevalRequest_(msg);
                otherwise
                    % Unhandled messages are ignored here; run loops will poll directly.
            end
        end

        function handleParfevalRequest_(obj, msg)
            if ~isfield(msg, "requestId") || ~isfield(msg, "fcn") || ~isfield(msg, "nOut") || ~isfield(msg, "args")
                return;
            end

            requestId = msg.requestId;
            fcn = msg.fcn;
            nOut = double(msg.nOut);
            args = msg.args;
            if ~iscell(args)
                args = {args};
            end

            requestedBy = "instrument";
            if isfield(msg, "requestedBy") && strlength(string(msg.requestedBy)) > 0
                requestedBy = string(msg.requestedBy);
            end
            obj.logClient_("parfeval request from worker: " + requestedBy + " -> " + func2str(fcn));

            ok = true;
            err = [];
            state = "";
            try
                fut = obj.parfevalOnClient(@measurementEngine.workerTaskMain_, nOut, ...
                    obj.workerFprintfQueue, requestedBy, fcn, args{:});
                try
                    if ~isempty(fut) && isprop(fut, "State")
                        state = fut.State;
                    end
                catch
                end
                if ~isempty(obj.spawnedFutures)
                    obj.spawnedFutures(end).requestedBy = requestedBy;
                end
            catch ME
                ok = false;
                err = measurementEngine.serializeException_(ME);
            end

            obj.safeSendToEngine_(struct( ...
                "type", "parfevalDone", ...
                "requestId", requestId, ...
                "ok", ok, ...
                "state", state, ...
                "error", err));
        end

        function safeSendToEngine_(obj, msg)
            if obj.constructionMode ~= "recipe"
                return;
            end
            if isempty(obj.clientToEngine)
                error("measurementEngine:EngineNotReady", "Engine worker command queue is not initialized.");
            end
            if isstruct(msg) && isfield(msg, "type")
                msgType = msg.type;
                if msgType ~= "ack"
                    rid = "";
                    if isfield(msg, "requestId")
                        rid = msg.requestId;
                    end
                    obj.logClient_("send->engine " + msgType + " " + rid);
                end
            end
            send(obj.clientToEngine, msg);
        end

        function reply = waitForEngineReply_(obj, requestId, expectedType)
            startTime = datetime("now");
            timeout = minutes(5);
            while true
                if ~isempty(obj.engineToClientBacklog)
                    for i = 1:numel(obj.engineToClientBacklog)
                        candidate = obj.engineToClientBacklog{i};
                        if ~isstruct(candidate) || ~isfield(candidate, "type") || ~isfield(candidate, "requestId")
                            continue;
                        end
                        if candidate.type == expectedType && candidate.requestId == requestId
                            reply = candidate;
                            obj.engineToClientBacklog(i) = [];
                            return;
                        end
                    end
                end

                while obj.engineToClient.QueueLength > 0
                    msg = poll(obj.engineToClient);
                    if isstruct(msg) && isfield(msg, "type")
                        msgType = msg.type;
                        if msgType == "parfeval"
                            obj.handleEngineToClientMessage_(msg);
                            continue;
                        end
                        if msgType == expectedType && isfield(msg, "requestId") && msg.requestId == requestId
                            reply = msg;
                            return;
                        end
                        if isfield(msg, "requestId")
                            obj.engineToClientBacklog{end+1} = msg;
                        end
                    end
                end
                assert(datetime("now") - startTime < timeout, "measurementEngine:Timeout", "Timed out waiting for engine reply %s.", expectedType);
                pause(0.001);
            end
        end

        function throwRemoteError_(~, reply)
            if isfield(reply, "error") && ~isempty(reply.error)
                err = reply.error;
                if isstruct(err) && isfield(err, "message")
                    error("measurementEngine:RemoteError", "%s", err.message);
                end
            end
            error("measurementEngine:RemoteError", "Remote operation failed.");
        end

        function chanSize = channelSizeOf_(obj, channelFriendlyName)
            arguments
                obj
                channelFriendlyName (1, 1) string
            end
            if obj.constructionMode == "rack"
                tbl = obj.rackLocal.channelTable;
                idx = find(tbl.channelFriendlyNames == channelFriendlyName, 1);
                assert(~isempty(idx), "measurementEngine:UnknownChannel", "Unknown channel %s.", channelFriendlyName);
                chanSize = double(tbl.channelSizes(idx));
                return;
            end

            idx = find(obj.channelFriendlyNames == channelFriendlyName, 1);
            assert(~isempty(idx), "measurementEngine:UnknownChannel", "Unknown channel %s.", channelFriendlyName);
            chanSize = double(obj.channelSizes(idx));
        end

        function dataOut = runLocal_(obj, scanObj, filename)
            rack = obj.rackLocal;
            if isempty(rack)
                error("measurementEngine:MissingRack", "Local rack is not available.");
            end

            tempFile = filename + "~";
            [dataOut, scanForSave, figHandle, pendingClose] = obj.runLocalCore_(rack, scanObj, tempFile);
            obj.saveFinal_(filename, scanForSave, dataOut, figHandle);
            if pendingClose && ~isempty(figHandle) && ishandle(figHandle)
                delete(figHandle);
            end
        end

        function dataOut = runOnWorker_(obj, scanObj, filename, mode)
            arguments
                obj
                scanObj (1, 1) measurementScan
                filename (1, 1) string {mustBeNonzeroLengthText}
                mode (1, 1) string {mustBeMember(mode, ["safe", "turbo"])}
            end

            scanObj.mode = mode;
            tempFile = filename + "~";
            [dataOut, scanForSave, figHandle, pendingClose] = obj.runWorkerCore_(scanObj, tempFile);
            obj.saveFinal_(filename, scanForSave, dataOut, figHandle);
            if pendingClose && ~isempty(figHandle) && ishandle(figHandle)
                delete(figHandle);
            end
        end

        function [dataOut, scanForSave, figHandle, pendingClose] = runLocalCore_(obj, rack, scanObj, tempFile)
            % Runs a scan against a local rack and updates GUI on the client.

            scanForSave = scanObj.toSaveStruct();
            [figHandle, plotState] = obj.initLiveFigure_(scanObj, scanForSave);

            pendingClose = false;
            lastCount = ones(1, plotState.nloops);

            set(figHandle, "CurrentCharacter", char(0));
            figHandle.UserData = struct("stopRequested", false);
            set(figHandle, "CloseRequestFcn", @onClose);

            function onClose(~, ~)
                selection = questdlg("Stop the scan and close this figure?", "Closing", "Stop", "Cancel", "Cancel");
                if selection ~= "Stop"
                    return;
                end
                figHandle.UserData.stopRequested = true;
                pendingClose = true;
            end

            function onRead(loopIdx, count, newdata, meta)
                if ~isempty(scanObj.disp)
                    plotValues = nan(numel(scanObj.disp), 1);
                    for k = 1:numel(scanObj.disp)
                        dc = scanObj.disp(k).channel;
                        if meta.dataloop(dc) ~= loopIdx
                            continue;
                        end
                        localIdx = dc - meta.offset0(loopIdx);
                        plotValues(k) = newdata(localIdx);
                    end
                    [plotState, lastCount] = obj.applySafePlotUpdate_(plotState, lastCount, loopIdx, count, plotValues);
                end
                drawnow;
            end

            function onTemp(~, data, ~)
                if strlength(tempFile) == 0
                    return;
                end
                try
                    savePayload = struct();
                    savePayload.scan = scanForSave;
                    savePayload.data = data;
                    save(tempFile, "-struct", "savePayload");
                catch
                end
            end

            scanStart = datetime("now");
            scanForSave.startTime = scanStart;
            dataOut = measurementEngine.runScanCore_(rack, scanObj, @onRead, figHandle, duration.empty, [], @onTemp);
            scanEnd = datetime("now");
            scanForSave.startTime = scanStart;
            scanForSave.endTime = scanEnd;
            scanForSave.duration = scanEnd - scanStart;
        end

        function [dataOut, scanForSave, figHandle, pendingClose] = runWorkerCore_(obj, scanObj, tempFile)
            % Runs a scan on the engine worker and updates GUI on the client.

            scanForSave = scanObj.toSaveStruct();

            [figHandle, plotState] = obj.initLiveFigure_(scanObj, scanForSave);
            stopRequested = false;
            stopSent = false;
            pendingClose = false;

            set(figHandle, "CurrentCharacter", char(0));
            set(figHandle, "CloseRequestFcn", @onClose);

            function onClose(~, ~)
                selection = questdlg("Stop the scan and close this figure?", "Closing", "Stop", "Cancel", "Cancel");
                if selection ~= "Stop"
                    return;
                end
                stopRequested = true;
                pendingClose = true;
            end

            function checkEsc()
                if isempty(figHandle) || ~ishandle(figHandle)
                    return;
                end
                try
                    current_char = get(figHandle, "CurrentCharacter");
                catch
                    return;
                end
                if isequal(current_char, char(27))
                    set(figHandle, "CurrentCharacter", char(0));
                    stopRequested = true;
                end
            end

            runId = obj.nextRequestId_();
            scanStart = datetime("now");
            scanForSave.startTime = scanStart;
            msg = struct("type", "run", "requestId", runId, "scan", scanObj);
            if scanObj.mode == "turbo"
                snapshotInterval = obj.turboSnapshotInterval;
                if ~(isduration(snapshotInterval) && isfinite(seconds(snapshotInterval)) && snapshotInterval > seconds(0))
                    error("measurementEngine:InvalidTurboInterval", "turboSnapshotInterval must be a finite, positive duration.");
                end
                msg.snapshotInterval = snapshotInterval;
            end
            obj.safeSendToEngine_(msg);
            obj.logClient_("run started " + runId + " mode=" + scanObj.mode + " name=" + scanObj.name);

            lastCount = ones(1, plotState.nloops);
            dataOut = {};
            gotAnyData = false;
            nextWaitLogTime = datetime("now") + seconds(2);
            sentFirstAck = false;

            function saveTemp(data)
                if strlength(tempFile) == 0
                    return;
                end
                try
                    savePayload = struct();
                    savePayload.scan = scanForSave;
                    savePayload.data = data;
                    save(tempFile, "-struct", "savePayload");
                catch
                end
            end

            done = false;
            while ~done
                checkEsc();
                % Turbo mode requirement:
                % - snapshot updates may accumulate; poll exactly the current queue length,
                %   and only plot the *latest* turbo snapshot payload.
                latestPlotData = {};
                hasLatestPlotData = false;
                latestTempData = {};
                hasLatestTempData = false;

                if ~isempty(obj.engineToClientBacklog)
                    backlog = obj.engineToClientBacklog;
                    obj.engineToClientBacklog = cell(1, 0);
                    for i = 1:numel(backlog)
                        msg = backlog{i};
                        if ~isstruct(msg) || ~isfield(msg, "type")
                            obj.engineToClientBacklog{end+1} = msg;
                            continue;
                        end
                        msgType = msg.type;
                        if msgType == "parfeval"
                            obj.handleEngineToClientMessage_(msg);
                            continue;
                        end
                        if ~isfield(msg, "requestId") || msg.requestId ~= runId
                            obj.engineToClientBacklog{end+1} = msg;
                            continue;
                        end

                        if msgType == "safePoint"
                            loopIdx = double(msg.loopIdx);
                            count = double(msg.count(:)).';
                            plotValues = double(msg.plotValues(:));
                            [plotState, lastCount] = obj.applySafePlotUpdate_(plotState, lastCount, loopIdx, count, plotValues);
                            drawnow;
                            checkEsc();
                            if stopRequested
                                if ~stopSent
                                    obj.safeSendToEngine_(struct("type", "stop", "requestId", runId));
                                    stopSent = true;
                                else
                                    obj.safeSendToEngine_(struct("type", "ack", "requestId", runId));
                                end
                            else
                                obj.safeSendToEngine_(struct("type", "ack", "requestId", runId));
                            end
                            continue;
                        end

                        if msgType == "turboSnapshot"
                            plotData = msg.plotData;
                            if ~iscell(plotData)
                                plotData = {plotData};
                            end
                            latestPlotData = plotData(:);
                            hasLatestPlotData = true;
                            continue;
                        end

                        if msgType == "tempData"
                            tmp = msg.data;
                            if ~iscell(tmp)
                                tmp = {tmp};
                            end
                            latestTempData = tmp;
                            hasLatestTempData = true;
                            continue;
                        end

                        if msgType == "runDone"
                            if isfield(msg, "ok") && ~logical(msg.ok)
                                obj.throwRemoteError_(msg);
                            end
                            if isfield(msg, "data")
                                dataOut = msg.data;
                            end
                            done = true;
                            continue;
                        end
                    end
                end

                qlen = obj.engineToClient.QueueLength;

                for q = 1:qlen
                    msg = poll(obj.engineToClient);
                    if ~isstruct(msg) || ~isfield(msg, "type")
                        continue;
                    end

                    msgType = msg.type;
                    if msgType == "parfeval"
                        obj.handleEngineToClientMessage_(msg);
                        continue;
                    end

                    if ~isfield(msg, "requestId")
                        continue;
                    end
                    if msg.requestId ~= runId
                        obj.engineToClientBacklog{end+1} = msg;
                        continue;
                    end

                    if msgType == "safePoint"
                        if ~gotAnyData
                            gotAnyData = true;
                            obj.logClient_("received first safePoint " + runId);
                        end
                        loopIdx = double(msg.loopIdx);
                        count = double(msg.count(:)).';
                        plotValues = double(msg.plotValues(:));
                        [plotState, lastCount] = obj.applySafePlotUpdate_(plotState, lastCount, loopIdx, count, plotValues);
                        drawnow;
                        checkEsc();
                        if stopRequested
                            if ~stopSent
                                obj.safeSendToEngine_(struct("type", "stop", "requestId", runId));
                                stopSent = true;
                            else
                                obj.safeSendToEngine_(struct("type", "ack", "requestId", runId));
                            end
                        else
                            if ~sentFirstAck && obj.verboseClient
                                sentFirstAck = true;
                                obj.logClient_("send first ack " + runId);
                            end
                            obj.safeSendToEngine_(struct("type", "ack", "requestId", runId));
                        end
                        continue;
                    end

                    if msgType == "turboSnapshot"
                        if ~gotAnyData
                            gotAnyData = true;
                            obj.logClient_("received first turboSnapshot " + runId);
                        end
                        plotData = msg.plotData;
                        if ~iscell(plotData)
                            plotData = {plotData};
                        end
                        latestPlotData = plotData(:);
                        hasLatestPlotData = true;
                        continue;
                    end

                    if msgType == "tempData"
                        tmp = msg.data;
                        if ~iscell(tmp)
                            tmp = {tmp};
                        end
                        latestTempData = tmp;
                        hasLatestTempData = true;
                        continue;
                    end

                    if msgType == "runDone"
                        if isfield(msg, "ok") && ~logical(msg.ok)
                            obj.throwRemoteError_(msg);
                        end
                        if isfield(msg, "data")
                            dataOut = msg.data;
                        end
                        obj.logClient_("runDone ok " + runId);
                        done = true;
                        continue;
                    end
                end

                if hasLatestPlotData
                    obj.applyTurboPlotUpdate_(plotState, latestPlotData);
                    drawnow limitrate;
                    checkEsc();
                end
                if hasLatestTempData
                    saveTemp(latestTempData);
                end

                if done
                    break;
                end

                if ~gotAnyData && obj.verboseClient && datetime("now") >= nextWaitLogTime
                    obj.logClient_("waiting for worker messages " + runId + " qlen=" + obj.engineToClient.QueueLength);
                    nextWaitLogTime = datetime("now") + seconds(2);
                end

                if stopRequested
                    if ~stopSent
                        obj.safeSendToEngine_(struct("type", "stop", "requestId", runId));
                        stopSent = true;
                    end
                end

                fut = obj.engineWorkerFuture_();
                if ~isempty(fut) && isprop(fut, "State") && fut.State ~= "running"
                    error("measurementEngine:EngineWorkerFailed", "Engine worker failed during run. State: %s", fut.State);
                end

                pause(0.01);
            end

            % If we exited early in turbo mode, drain any remaining snapshots and
            % update the GUI once more before saving/export.
            if stopRequested && scanObj.mode == "turbo"
                qlen = obj.engineToClient.QueueLength;
                latestPlotData = {};
                hasLatestPlotData = false;
                latestTempData = {};
                hasLatestTempData = false;
                for q = 1:qlen
                    msg = poll(obj.engineToClient);
                    if ~isstruct(msg) || ~isfield(msg, "type")
                        continue;
                    end

                    msgType = msg.type;
                    if msgType == "parfeval"
                        obj.handleEngineToClientMessage_(msg);
                        continue;
                    end
                    if ~isfield(msg, "requestId")
                        continue;
                    end
                    if msg.requestId ~= runId
                        obj.engineToClientBacklog{end+1} = msg;
                        continue;
                    end
                    if msgType == "turboSnapshot"
                        plotData = msg.plotData;
                        if ~iscell(plotData)
                            plotData = {plotData};
                        end
                        latestPlotData = plotData(:);
                        hasLatestPlotData = true;
                    end
                    if msgType == "tempData"
                        tmp = msg.data;
                        if ~iscell(tmp)
                            tmp = {tmp};
                        end
                        latestTempData = tmp;
                        hasLatestTempData = true;
                    end
                end

                if hasLatestPlotData
                    obj.applyTurboPlotUpdate_(plotState, latestPlotData);
                    drawnow limitrate;
                end
                if hasLatestTempData
                    saveTemp(latestTempData);
                end
            end

            scanEnd = datetime("now");
            scanForSave.startTime = scanStart;
            scanForSave.endTime = scanEnd;
            scanForSave.duration = scanEnd - scanStart;
        end

        function [figHandle, plotState] = initLiveFigure_(obj, scanObj, scanForSave)
            dispEntries = scanObj.disp;
            numDisp = numel(dispEntries);

            figNum = 1000;
            if isfield(scanForSave, "figure") && ~isempty(scanForSave.figure) && ~isnan(scanForSave.figure)
                figNum = double(scanForSave.figure);
            end

            if ishandle(figNum)
                figHandle = figure(figNum);
                clf(figHandle);
            else
                figHandle = figure(figNum);
                try
                    figHandle.WindowState = "maximized";
                catch
                end
                drawnow;
            end

            modeLabel = "single threaded";
            if obj.constructionMode == "recipe"
                if scanObj.mode == "turbo"
                    modeLabel = "turbo mode";
                else
                    modeLabel = "safe mode";
                end
            end
            titleText = "SM - " + modeLabel;
            if strlength(scanObj.name) > 0
                titleText = titleText + " - " + scanObj.name;
            end
            try
                figHandle.NumberTitle = "off";
                figHandle.Name = char(titleText);
            catch
            end

            meta = measurementEngine.computeScanMeta_(scanObj);
            sbpl = measurementEngine.subplotShape_(numDisp);

            plotState = struct();
            plotState.figHandle = figHandle;
            plotState.disp = dispEntries;
            plotState.handles = gobjects(1, numDisp);
            plotState.nloops = meta.nloops;
            plotState.npoints = meta.npoints;
            plotState.xLoop = zeros(1, numDisp);
            plotState.yLoop = zeros(1, numDisp);
            plotState.oneDData = cell(1, numDisp);
            plotState.twoDData = cell(1, numDisp);

            for k = 1:numDisp
                subplot(sbpl(1), sbpl(2), k, "Parent", figHandle);

                dc = dispEntries(k).channel;
                dim = dispEntries(k).dim;
                assert(dc >= 1 && dc <= numel(meta.dataloop), "measurementEngine:InvalidDispChannel", "Invalid disp channel index %d.", dc);
                xLoop = meta.dataloop(dc);
                plotState.xLoop(k) = xLoop;

                if dim == 2 && xLoop < meta.nloops
                    yLoop = xLoop + 1;
                    plotState.yLoop(k) = yLoop;

                    [xAxis, xLabel] = measurementEngine.buildLoopAxis_(scanObj, xLoop);
                    [yAxis, yLabel] = measurementEngine.buildLoopAxis_(scanObj, yLoop);
                    z0 = nan(numel(yAxis), numel(xAxis));
                    plotState.twoDData{k} = z0;
                    plotState.handles(k) = imagesc(xAxis, yAxis, z0);
                    set(gca, "YDir", "normal");
                    colorbar;
                    xlabel(strrep(xLabel, "_", "\_"));
                    ylabel(strrep(yLabel, "_", "\_"));
                else
                    [xAxis, xLabel] = measurementEngine.buildLoopAxis_(scanObj, xLoop);
                    y0 = nan(1, numel(xAxis));
                    plotState.oneDData{k} = y0;
                    plotState.handles(k) = plot(xAxis, y0);
                    xlim(measurementEngine.computeAxisLimits_(xAxis));
                    xlabel(strrep(xLabel, "_", "\_"));
                end

                if dc >= 1 && dc <= numel(scanObj.flatScalarGetNames)
                    chName = scanObj.flatScalarGetNames(dc);
                    title(strrep(chName, "_", "\_"));
                    ylabel(strrep(chName, "_", "\_"));
                end
            end

            % Ensure the empty plots render before the first data update.
            drawnow;
        end

        function [plotState, lastCount] = applySafePlotUpdate_(~, plotState, lastCount, loopIdx, count, plotValues)
            arguments
                ~
                plotState (1, 1) struct
                lastCount (1, :) double
                loopIdx (1, 1) double {mustBePositive, mustBeInteger}
                count (1, :) double {mustBePositive, mustBeInteger}
                plotValues (:, 1) double
            end
            if isempty(plotState.disp)
                lastCount = count;
                return;
            end

            nloops = plotState.nloops;
            if numel(count) ~= nloops
                error("measurementEngine:InvalidCount", "Expected count length %d, got %d.", nloops, numel(count));
            end

            outerChanged = count ~= lastCount;

            for k = 1:numel(plotState.disp)
                dim = plotState.disp(k).dim;
                xLoop = plotState.xLoop(k);

                if dim == 2 && plotState.yLoop(k) > 0
                    yLoop = plotState.yLoop(k);

                    if yLoop < nloops && any(outerChanged(yLoop+1:end))
                        plotState.twoDData{k}(:) = NaN;
                        set(plotState.handles(k), "CData", plotState.twoDData{k});
                    end

                    if loopIdx == xLoop && k <= numel(plotValues) && ~isnan(plotValues(k))
                        z = plotState.twoDData{k};
                        z(count(yLoop), count(xLoop)) = plotValues(k);
                        plotState.twoDData{k} = z;
                        if count(xLoop) == plotState.npoints(xLoop)
                            set(plotState.handles(k), "CData", z);
                        end
                    end
                else
                    if xLoop < nloops && any(outerChanged(xLoop+1:end))
                        plotState.oneDData{k}(:) = NaN;
                        set(plotState.handles(k), "YData", plotState.oneDData{k});
                    end

                    if loopIdx == xLoop && k <= numel(plotValues) && ~isnan(plotValues(k))
                        y = plotState.oneDData{k};
                        y(count(xLoop)) = plotValues(k);
                        plotState.oneDData{k} = y;
                        set(plotState.handles(k), "YData", y);
                    end
                end
            end

            lastCount = count;
        end

        function applyTurboPlotUpdate_(~, plotState, plotData)
            arguments
                ~
                plotState (1, 1) struct
                plotData (:, 1) cell
            end
            if isempty(plotState.disp)
                return;
            end

            n = min(numel(plotState.disp), numel(plotData));
            for k = 1:n
                dim = plotState.disp(k).dim;
                if dim == 2 && plotState.yLoop(k) > 0
                    set(plotState.handles(k), "CData", plotData{k});
                else
                    y = plotData{k};
                    set(plotState.handles(k), "YData", y(:).');
                end
            end
        end

        function saveFinal_(~, filename, scanForSave, data, figHandle)
            arguments
                ~
                filename (1, 1) string {mustBeNonzeroLengthText}
                scanForSave (1, 1) struct
                data (1, :) cell
                figHandle = []
            end
            if isempty(figHandle) || ~ishandle(figHandle)
                try
                    figHandle = gcf;
                catch
                    figHandle = [];
                end
            end
            closeDialogShown = false;
            if ~isempty(figHandle) && ishandle(figHandle)
                set(figHandle, "CloseRequestFcn", @onCloseWhileSaving);
            end

            savePayload = struct();
            savePayload.scan = scanForSave;
            savePayload.data = data;
            save(filename, "-struct", "savePayload");
            try
                [scanPath, scanName] = fileparts(filename);
                scanFile = fullfile(scanPath, scanName + "_scan.mat");
                scanPayload = struct();
                scanPayload.scan = scanForSave;
                save(scanFile, "-struct", "scanPayload");
            catch
            end
            try
                tempFile = filename + "~";
                if isfile(tempFile)
                    delete(tempFile);
                end
            catch
            end

            % PNG + PPT + FIG mirror legacy smrun behavior.
            if isempty(figHandle) || ~ishandle(figHandle)
                return;
            end

            [figpath, figname] = fileparts(filename);
            if isempty(figname)
                figstring = filename;
            elseif isempty(figpath)
                figstring = figname;
            else
                figstring = fullfile(figpath, figname);
            end

            exportFig = figHandle;
            useExportCopy = false;
            try
                exportFig = figure(Visible = "off");
                useExportCopy = true;
                copyobj(figHandle.Children, exportFig);
                try
                    exportFig.Colormap = figHandle.Colormap;
                catch
                end
                try
                    ax = findall(exportFig, "Type", "axes");
                    for axIdx = 1:numel(ax)
                        try
                            if isprop(ax(axIdx), "Toolbar") && ~isempty(ax(axIdx).Toolbar)
                                ax(axIdx).Toolbar.Visible = "off";
                            end
                        catch
                        end
                        try
                            disableDefaultInteractivity(ax(axIdx));
                        catch
                        end
                    end
                catch
                end
            catch
                if useExportCopy && ~isempty(exportFig) && ishandle(exportFig)
                    delete(exportFig);
                end
                exportFig = figHandle;
                useExportCopy = false;
            end

            pngFile = sprintf("%s.png", figstring);
            png_saved = true;
            pptEnabled = false;
            pptFile = "";
            try
                [pptEnabled, pptFile] = smpptGetState();
            catch
            end
            try
                if ~isMATLABReleaseOlderThan("R2025a") && pptEnabled
                    % Export at a fixed pixel size for PPT. Width is fixed; height is
                    % slightly taller so the inserted image fills more of the slide.
                    exportWidthPx = 2560;
                    exportHeightPx = 1300;
                    try
                        exportFig.Units = "pixels";
                        exportFig.Position(3:4) = [exportWidthPx, exportHeightPx];
                    catch
                    end
                    exportgraphics(exportFig, pngFile, ...
                        Units = "pixels", Width = exportWidthPx, Height = exportHeightPx, ...
                        Padding = "tight", PreserveAspectRatio = "on");
                elseif isMATLABReleaseOlderThan("R2025a")
                    exportgraphics(exportFig, pngFile, Resolution = 300);
                else
                    exportgraphics(exportFig, pngFile, Resolution = 300, Padding = "tight");
                end
            catch
                png_saved = false;
            end

            % Save PowerPoint if enabled
            try
                if pptEnabled
                    pptFile = string(pptFile);
                    if strlength(pptFile) == 0
                        % no file
                    elseif ~png_saved
                        % no png
                    else
                        text_data = struct();
                        [~, name_only, ext] = fileparts(filename);
                        text_data.title = char(name_only + ext);
                        headerLines = strings(0, 1);
                        if isfield(scanForSave, "duration") && isduration(scanForSave.duration) && isfinite(seconds(scanForSave.duration))
                            headerLines(end+1) = "duration: " + string(scanForSave.duration);
                        end
                        if ~isempty(headerLines)
                            text_data.header = char(strjoin(headerLines, newline));
                        else
                            text_data.header = '';
                        end
                        if isfield(scanForSave, "consts")
                            text_data.consts = scanForSave.consts;
                        else
                            text_data.consts = [];
                        end
                        if isfield(scanForSave, "comments") && ~isempty(scanForSave.comments)
                            if iscell(scanForSave.comments)
                                text_data.body = char(scanForSave.comments{:});
                            elseif ischar(scanForSave.comments)
                                text_data.body = scanForSave.comments;
                            else
                                text_data.body = char(scanForSave.comments);
                            end
                        else
                            text_data.body = '';
                        end
                        [pptPath, pptName, pptExt] = fileparts(pptFile);
                        if strlength(pptExt) == 0
                            pptExt = ".ppt";
                        end
                        if strlength(pptPath) == 0
                            rootPath = experimentContext.getExperimentRootPath();
                            if strlength(rootPath) == 0
                                rootPath = string(pwd);
                            end
                            pptFile = fullfile(rootPath, pptName + pptExt);
                        else
                            pptFile = fullfile(pptPath, pptName + pptExt);
                        end

                        text_data.imagePath = pngFile;
                        smsaveppt(char(pptFile), text_data);
                    end
                end
            catch
            end

            try
                savefig(exportFig, figstring);
            catch
            end

            if useExportCopy && ~isempty(exportFig) && ishandle(exportFig)
                delete(exportFig);
            end

            try
                if ishandle(figHandle)
                    set(figHandle, "CloseRequestFcn", "closereq");
                end
            catch
            end

            function onCloseWhileSaving(~, ~)
                if closeDialogShown
                    return;
                end
                closeDialogShown = true;
                msgbox("Scan finished. Saving data, please wait.", "Saving", "help");
            end
        end
    end

    methods (Static, Access = private)
        function id = nextRequestId_()
            id = string(java.util.UUID.randomUUID());
        end

        function logDir = defaultLogDir_()
            rootPath = experimentContext.getExperimentRootPath();
            if strlength(rootPath) == 0
                rootPath = string(pwd);
            end
            logDir = fullfile(rootPath, "logs");
            if ~exist(logDir, "dir")
                [ok, msg] = mkdir(logDir);
                if ~ok
                    error("measurementEngine:LogDirCreateFailed", "Failed to create log dir %s. %s", logDir, msg);
                end
            end
        end

        function file = makeDefaultLogFile_(header)
            arguments
                header (1, 1) string
            end
            logDir = measurementEngine.defaultLogDir_();
            ts = char(datetime("now", "Format", "yyyyMMdd_HHmmss_SSS"));
            file = fullfile(logDir, header + "_" + ts + ".log");
        end

        function err = serializeException_(ME)
            err = struct();
            err.identifier = string(ME.identifier);
            err.message = string(ME.message);
            if ~isempty(ME.stack)
                err.stack = ME.stack;
            else
                err.stack = [];
            end
        end

        function rack = buildRackFromRecipe_(recipe, spawnOnClientFcn)
            if nargin < 2
                spawnOnClientFcn = [];
            end

            rack = instrumentRack(true);
            assignin("base", "rack", rack);
            if isempty(spawnOnClientFcn)
                assignin("base", "sm_spawnOnClient", []);
            else
                assignin("base", "sm_spawnOnClient", spawnOnClientFcn);
            end

            % Build hardware instruments.
            for k = 1:numel(recipe.instrumentSteps)
                step = recipe.instrumentSteps(k);
                className = step.className;
                ctorArgs = step.positionalArgs;
                nv = step.nameValuePairs;
                if ~iscell(ctorArgs)
                    ctorArgs = {ctorArgs};
                end
                if ~iscell(nv)
                    nv = {nv};
                end
                inst = feval(className, ctorArgs{:}, nv{:});
                inst.validateWorkersRequestedFromRecipe(double(step.numeWorkersRequested));
                assignin("base", char(step.handleVar), inst);
                rack.addInstrument(inst, step.friendlyName);
            end

            % Build channels for hardware instruments first.
            virtualSteps = struct([]);
            if isprop(recipe, "virtualInstrumentSteps")
                virtualSteps = recipe.virtualInstrumentSteps;
            end
            virtualNames = string.empty(0, 1);
            if ~isempty(virtualSteps)
                virtualNames = string({virtualSteps.friendlyName});
                if isrow(virtualNames)
                    virtualNames = virtualNames.';
                end
            end
            pendingVirtualChannel = false(1, numel(recipe.channelSteps));
            for k = 1:numel(recipe.channelSteps)
                step = recipe.channelSteps(k);
                pendingVirtualChannel(k) = any(step.instrumentFriendlyName == virtualNames);
                if pendingVirtualChannel(k)
                    continue;
                end
                rack.addChannel( ...
                    step.instrumentFriendlyName, ...
                    step.channel, ...
                    step.channelFriendlyName, ...
                    step.rampRates, ...
                    step.rampThresholds, ...
                    step.softwareMins, ...
                    step.softwareMaxs);
            end

            % Build virtual instruments (they receive the master rack during construction),
            % then add their channels.
            for vIdx = 1:numel(virtualSteps)
                step = virtualSteps(vIdx);
                className = step.className;
                ctorArgs = step.positionalArgs;
                nv = step.nameValuePairs;
                if ~iscell(ctorArgs)
                    ctorArgs = {ctorArgs};
                end
                if isempty(ctorArgs)
                    ctorArgs = {step.friendlyName};
                end
                if ~iscell(nv)
                    nv = {nv};
                end

                inst = feval(className, ctorArgs{1}, rack, ctorArgs{2:end}, nv{:});
                inst.validateWorkersRequestedFromRecipe(double(step.numeWorkersRequested));
                assignin("base", char(step.handleVar), inst);
                rack.addInstrument(inst, step.friendlyName);

                for k = 1:numel(recipe.channelSteps)
                    if ~pendingVirtualChannel(k)
                        continue;
                    end
                    chStep = recipe.channelSteps(k);
                    if chStep.instrumentFriendlyName ~= step.friendlyName
                        continue;
                    end
                    rack.addChannel( ...
                        chStep.instrumentFriendlyName, ...
                        chStep.channel, ...
                        chStep.channelFriendlyName, ...
                        chStep.rampRates, ...
                        chStep.rampThresholds, ...
                        chStep.softwareMins, ...
                        chStep.softwareMaxs);
                    pendingVirtualChannel(k) = false;
                end
            end
            if any(pendingVirtualChannel)
                bad = string({recipe.channelSteps(pendingVirtualChannel).instrumentFriendlyName});
                bad = unique(bad(:));
                error("measurementEngine:RecipeVirtualChannelsUnresolved", ...
                    "Channel steps refer to virtual instrument(s) that were not constructed: %s", strjoin(bad, ", "));
            end

            % Additional statements.
            for k = 1:numel(recipe.statements)
                evalin("base", char(recipe.statements(k)));
            end

            rack.flush();
        end

        function meta = computeScanMeta_(scanObj)
            nloops = numel(scanObj.loops);
            npoints = zeros(1, nloops);
            for k = 1:nloops
                npoints(k) = double(scanObj.loops(k).npoints);
            end

            if isempty(scanObj.scalarGetNamesByLoop) || numel(scanObj.scalarGetNamesByLoop) ~= nloops
                error("measurementEngine:MissingScalarGetNames", "scanObj.scalarGetNamesByLoop must be populated for all loops.");
            end

            nScalarGet = zeros(1, nloops);
            for k = 1:nloops
                nScalarGet(k) = numel(scanObj.scalarGetNamesByLoop{k});
            end

            offset0 = zeros(1, nloops);
            for k = 2:nloops
                offset0(k) = offset0(k-1) + nScalarGet(k-1);
            end

            totalScalar = sum(nScalarGet);
            dataloop = zeros(1, totalScalar);
            for loopIdx = 1:nloops
                if nScalarGet(loopIdx) == 0
                    continue;
                end
                idxs = (offset0(loopIdx) + 1):(offset0(loopIdx) + nScalarGet(loopIdx));
                dataloop(idxs) = loopIdx;
            end

            meta = struct();
            meta.nloops = nloops;
            meta.npoints = npoints;
            meta.nScalarGet = nScalarGet;
            meta.offset0 = offset0;
            meta.dataloop = dataloop;
            meta.totalScalar = totalScalar;
        end

        function sbpl = subplotShape_(numDisp)
            switch numDisp
                case 0
                    sbpl = [1 1];
                case 1
                    sbpl = [1 1];
                case 2
                    sbpl = [1 2];
                case {3, 4}
                    sbpl = [2 2];
                case {5, 6}
                    sbpl = [2 3];
                case {7, 8, 9}
                    sbpl = [3 3];
                case {10, 11, 12}
                    sbpl = [3 4];
                case {13, 14, 15, 16}
                    sbpl = [4 4];
                case {17, 18, 19, 20}
                    sbpl = [4 5];
                case {21, 22, 23, 24, 25}
                    sbpl = [5 5];
                case {26, 27, 28, 29, 30}
                    sbpl = [5 6];
                otherwise
                    sbpl = [6 6];
            end
        end

        function [axisValues, axisLabel] = buildLoopAxis_(scanObj, loopIdx)
            axisValues = [];
            axisLabel = "n";

            nloops = numel(scanObj.loops);
            if ~(loopIdx >= 1 && loopIdx <= nloops)
                return;
            end

            totalPoints = double(scanObj.loops(loopIdx).npoints);
            loopDef = scanObj.loops(loopIdx);

            if totalPoints > 0
                if isfield(loopDef, "setchanranges") && ~isempty(loopDef.setchanranges) && iscell(loopDef.setchanranges)
                    firstRange = loopDef.setchanranges{1};
                    if numel(firstRange) >= 2 && totalPoints > 1
                        axisValues = linspace(firstRange(1), firstRange(2), totalPoints);
                    elseif ~isempty(firstRange)
                        axisValues = repmat(firstRange(1), 1, totalPoints);
                    end
                elseif isfield(loopDef, "rng") && ~isempty(loopDef.rng) && numel(loopDef.rng) >= 2
                    if totalPoints > 1
                        axisValues = linspace(loopDef.rng(1), loopDef.rng(2), totalPoints);
                    else
                        axisValues = repmat(loopDef.rng(1), 1, totalPoints);
                    end
                end

                if isempty(axisValues)
                    axisValues = 1:totalPoints;
                end
            end

            if isfield(loopDef, "setchan") && ~isempty(loopDef.setchan)
                axisLabel = string(loopDef.setchan(1));
                if strlength(axisLabel) == 0
                    axisLabel = "n";
                end
            end

            axisValues = double(axisValues(:).');
        end

        function limits = computeAxisLimits_(axisValues)
            axisValues = double(axisValues(:));
            if isempty(axisValues)
                limits = [0 1];
                return;
            end

            minVal = min(axisValues);
            maxVal = max(axisValues);
            if minVal == maxVal
                delta = max(abs(minVal) * 0.05, 1);
                if delta == 0
                    delta = 1;
                end
                limits = [minVal - delta, maxVal + delta];
            else
                limits = [minVal, maxVal];
            end
        end

        function data = runScanCore_(rack, scanObj, onRead, figHandle, snapshotInterval, onSnapshot, onTemp, logFcn)
            % Single-threaded scan loop. Stop via figure handle (ESC + UserData.stopRequested).
            if nargin < 5
                snapshotInterval = duration.empty;
            end
            if nargin < 6
                onSnapshot = [];
            end
            if nargin < 7
                onTemp = [];
            end
            if nargin < 8
                logFcn = [];
            end

            enableLog = ~isempty(logFcn) && isa(logFcn, "function_handle");
            didLogFirstSet = false;
            didLogFirstGet = false;
            didLogFirstConstSet = false;

            % Stop via figure handle: ESC key + UserData.stopRequested flag.
            stopped = false;

            rack.flush();
            if enableLog
                logFcn("runScanCore_ start name=" + scanObj.name + " loops=" + numel(scanObj.loops));
            end

            if ~isempty(scanObj.consts)
                consts = scanObj.consts;
                if ~isfield(consts, "set")
                    [consts.set] = deal(1);
                end
                setMask = [consts.set] == 1;
                if any(setMask)
                    setchans = string({consts(setMask).setchan});
                    if isrow(setchans)
                        setchans = setchans.';
                    end
                    setvals = double([consts(setMask).val]).';
                    if enableLog && ~didLogFirstConstSet
                        didLogFirstConstSet = true; %#ok<NASGU>
                        logFcn("runScanCore_ const rackSet n=" + numel(setchans));
                    end
                    rack.rackSet(setchans, setvals);
                end
            end

            meta = measurementEngine.computeScanMeta_(scanObj);
            nloops = meta.nloops;
            npoints = meta.npoints;

            setchansByLoop = cell(1, nloops);
            getchansByLoop = cell(1, nloops);
            startwaitByLoop = repmat(seconds(0), 1, nloops);
            waittimeByLoop = repmat(seconds(0), 1, nloops);
            for loopIdx = 1:nloops
                loopDef = scanObj.loops(loopIdx);
                setchansByLoop{loopIdx} = string(loopDef.setchan(:));
                getchansByLoop{loopIdx} = string(loopDef.getchan(:));

                if isfield(loopDef, "startwait") && ~isempty(loopDef.startwait)
                    sw = loopDef.startwait;
                    if ~isduration(sw)
                        sw = seconds(double(sw));
                    end
                    startwaitByLoop(loopIdx) = sw;
                end
                if isfield(loopDef, "waittime") && ~isempty(loopDef.waittime)
                    wt = loopDef.waittime;
                    if ~isduration(wt)
                        wt = seconds(double(wt));
                    end
                    waittimeByLoop(loopIdx) = wt;
                end
            end

            % Allocate full data set (all scalar get channels).
            data = cell(1, meta.totalScalar);
            dataDimsByLoop = cell(1, nloops);
            dataStrideByLoop = cell(1, nloops);
            for loopIdx = 1:nloops
                baseDim = npoints(end:-1:loopIdx);
                if isempty(baseDim)
                    baseDim = 1;
                end
                if isscalar(baseDim)
                    baseDim(2) = 1;
                end
                dataDimsByLoop{loopIdx} = baseDim;
                dataStrideByLoop{loopIdx} = [1 cumprod(baseDim(1:end-1))];
                for k = 1:meta.nScalarGet(loopIdx)
                    ind = meta.offset0(loopIdx) + k;
                    data{ind} = nan(baseDim);
                end
            end

            enableSnapshot = isduration(snapshotInterval) && ~isempty(onSnapshot) && snapshotInterval > seconds(0);
            snapshotInterval_s = 0;
            lastSnapshotTic = [];
            if enableSnapshot
                snapshotInterval_s = seconds(snapshotInterval);
                lastSnapshotTic = tic;
            end

            enableTemp = ~isempty(onTemp) && isa(onTemp, "function_handle");
            saveLoopIdx = NaN;
            saveMinInterval_s = NaN;
            lastTempSaveTic = [];
            if enableTemp
                saveLoopIdx = double(scanObj.saveloop);
                if ~(isfinite(saveLoopIdx) && saveLoopIdx >= 1 && saveLoopIdx <= nloops && mod(saveLoopIdx, 1) == 0)
                    error("measurementEngine:InvalidSaveLoop", "saveloop must be an integer in [1, %d].", nloops);
                end
                saveMinInterval_s = seconds(scanObj.saveMinInterval);
                if ~(isfinite(saveMinInterval_s) && saveMinInterval_s > 0)
                    error("measurementEngine:InvalidSaveMinInterval", "saveMinInterval must be a finite, positive duration.");
                end
            end

            count = ones(1, nloops);
            totpoints = prod(npoints);

            for pointIdx = 1:totpoints
                % Stop check (figure handle)
                if ~stopped
                    try
                        if isequal(get(figHandle, "CurrentCharacter"), char(27))
                            set(figHandle, "CurrentCharacter", char(0));
                            stopped = true;
                        end
                        ud = figHandle.UserData;
                        if isstruct(ud) && ud.stopRequested
                            stopped = true;
                        end
                    catch
                    end
                end
                if stopped, break; end

                if enableSnapshot && toc(lastSnapshotTic) >= snapshotInterval_s
                    onSnapshot(count, data, meta);
                    lastSnapshotTic = tic;
                end

                % --- Determine which loops need setting ---
                if pointIdx == 1
                    loopsToSet = 1:nloops;
                else
                    loops_end_idx = find(count > 1, 1, "first");
                    if isempty(loops_end_idx)
                        loops_end_idx = nloops;
                    end
                    loopsToSet = 1:loops_end_idx;
                end

                for loopIdx = fliplr(loopsToSet)
                    if ~stopped
                        try
                            if isequal(get(figHandle, "CurrentCharacter"), char(27))
                                set(figHandle, "CurrentCharacter", char(0));
                                stopped = true;
                            end
                            ud = figHandle.UserData;
                            if isstruct(ud) && ud.stopRequested
                                stopped = true;
                            end
                        catch
                        end
                    end
                    if stopped, break; end

                    loopDef = scanObj.loops(loopIdx);
                    setchans = setchansByLoop{loopIdx};
                    if isempty(setchans)
                        continue;
                    end

                    vals = nan(numel(setchans), 1);
                    if isfield(loopDef, "setchanranges") && ~isempty(loopDef.setchanranges) && iscell(loopDef.setchanranges)
                        num_ranges = min(numel(setchans), numel(loopDef.setchanranges));
                        for k = 1:num_ranges
                            r = loopDef.setchanranges{k};
                            if isempty(r)
                                continue;
                            end
                            if npoints(loopIdx) > 1 && numel(r) >= 2
                                vals(k) = r(1) + (r(2) - r(1)) * (count(loopIdx) - 1) / (npoints(loopIdx) - 1);
                            else
                                vals(k) = r(1);
                            end
                        end
                        vals(isnan(vals)) = count(loopIdx);
                    elseif isfield(loopDef, "rng") && ~isempty(loopDef.rng) && numel(loopDef.rng) >= 2
                        r = loopDef.rng;
                        if npoints(loopIdx) > 1
                            vals(:) = r(1) + (r(2) - r(1)) * (count(loopIdx) - 1) / (npoints(loopIdx) - 1);
                        else
                            vals(:) = r(1);
                        end
                    else
                        vals(:) = count(loopIdx);
                    end

                    if enableLog && ~didLogFirstSet
                        didLogFirstSet = true;
                        pairs = compose("%s=%g", setchans(:), vals(:));
                        logFcn("runScanCore_ first rackSet loop=" + loopIdx + " " + strjoin(pairs, ", "));
                    end
                    rack.rackSet(setchans, vals);

                    if count(loopIdx) == 1
                        measurementEngine.waitWithStop_(startwaitByLoop(loopIdx), figHandle);
                    end

                    measurementEngine.waitWithStop_(waittimeByLoop(loopIdx), figHandle);
                end

                if ~stopped
                    try
                        if isequal(get(figHandle, "CurrentCharacter"), char(27))
                            set(figHandle, "CurrentCharacter", char(0));
                            stopped = true;
                        end
                        ud = figHandle.UserData;
                        if isstruct(ud) && ud.stopRequested
                            stopped = true;
                        end
                    catch
                    end
                end
                if stopped, break; end

                % --- Determine which loops should be read ---
                if pointIdx == 1
                    loopsToRead = 1:nloops;
                else
                    loops_end_idx = find(count < npoints, 1, "first");
                    if isempty(loops_end_idx)
                        loops_end_idx = nloops;
                    end
                    loopsToRead = 1:loops_end_idx;
                end

                for loopIdx = loopsToRead
                    if ~stopped
                        try
                            if isequal(get(figHandle, "CurrentCharacter"), char(27))
                                set(figHandle, "CurrentCharacter", char(0));
                                stopped = true;
                            end
                            ud = figHandle.UserData;
                            if isstruct(ud) && ud.stopRequested
                                stopped = true;
                            end
                        catch
                        end
                    end
                    if stopped, break; end

                    getchans = getchansByLoop{loopIdx};

                    if ~isempty(getchans) && meta.nScalarGet(loopIdx) > 0
                        if enableLog && ~didLogFirstGet
                            didLogFirstGet = true;
                            logFcn("runScanCore_ first rackGet loop=" + loopIdx + " n=" + numel(getchans));
                        end
                        newdata = rack.rackGet(getchans);
                        newdata = double(newdata(:));
                        assert(numel(newdata) == meta.nScalarGet(loopIdx), "measurementEngine:BadGetLength", ...
                            "Expected %d get values for loop %d, got %d.", meta.nScalarGet(loopIdx), loopIdx, numel(newdata));

                        dims = dataDimsByLoop{loopIdx};
                        stride = dataStrideByLoop{loopIdx};
                        subsVec = count(nloops:-1:loopIdx);
                        if numel(subsVec) < numel(dims)
                            subsVec(end+1:numel(dims)) = 1;
                        end
                        linIdx = 1 + sum((subsVec - 1) .* stride);
                        for k = 1:meta.nScalarGet(loopIdx)
                            ind = meta.offset0(loopIdx) + k;
                            data{ind}(linIdx) = newdata(k);
                        end

                        onRead(loopIdx, count, newdata, meta);
                        if enableSnapshot && toc(lastSnapshotTic) >= snapshotInterval_s
                            onSnapshot(count, data, meta);
                            lastSnapshotTic = tic;
                        end
                    end

                    if enableTemp && loopIdx == saveLoopIdx
                        if isempty(lastTempSaveTic) || toc(lastTempSaveTic) >= saveMinInterval_s
                            onTemp(count, data, meta);
                            lastTempSaveTic = tic;
                        end
                    end
                end

                if ~stopped
                    try
                        if isequal(get(figHandle, "CurrentCharacter"), char(27))
                            set(figHandle, "CurrentCharacter", char(0));
                            stopped = true;
                        end
                        ud = figHandle.UserData;
                        if isstruct(ud) && ud.stopRequested
                            stopped = true;
                        end
                    catch
                    end
                end
                if stopped, break; end

                % --- Update counters ---
                j = 1;
                while j <= numel(loopsToRead)
                    loopIdx = loopsToRead(j);
                    if count(loopIdx) < npoints(loopIdx)
                        count(loopIdx) = count(loopIdx) + 1;
                        break;
                    else
                        count(loopIdx) = 1;
                        j = j + 1;
                    end
                end
            end

            if enableSnapshot
                onSnapshot(count, data, meta);
            end
        end

        function waitWithStop_(waitDuration, figHandle)
            % Interruptible wait using figure handle for stop checking.
            if isempty(waitDuration)
                return;
            end
            if ~isduration(waitDuration)
                waitDuration = seconds(double(waitDuration));
            end
            waitSeconds = seconds(waitDuration);
            if ~(isfinite(waitSeconds) && waitSeconds > 0)
                return;
            end

            maxStep_s = 0.05;
            remaining = waitSeconds;
            while remaining > 0
                try
                    if isequal(get(figHandle, "CurrentCharacter"), char(27))
                        set(figHandle, "CurrentCharacter", char(0));
                        return;
                    end
                    ud = figHandle.UserData;
                    if isstruct(ud) && ud.stopRequested
                        return;
                    end
                catch
                end
                step = min(maxStep_s, remaining);
                pause(step);
                remaining = remaining - step;
            end
        end

        function [data, plotData, stopped] = runTurboScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, snapshotInterval, logFcn)
            % Turbo scan loop: periodic snapshot updates, no per-point ACK.
            % Stop: poll clientToEngine PDQ, verify type == "stop".
            enableLog = ~isempty(logFcn) && isa(logFcn, "function_handle");
            meta = measurementEngine.computeScanMeta_(scanObj);
            nloops = meta.nloops;
            npoints = meta.npoints;

            % Precompute per-loop channels and wait durations (seconds).
            setchansByLoop = cell(1, nloops);
            getchansByLoop = cell(1, nloops);
            startwait_s = zeros(1, nloops);
            waittime_s = zeros(1, nloops);
            for li = 1:nloops
                ld = scanObj.loops(li);
                setchansByLoop{li} = string(ld.setchan(:));
                getchansByLoop{li} = string(ld.getchan(:));
                if isfield(ld, "startwait") && ~isempty(ld.startwait)
                    sw = ld.startwait; if isduration(sw), sw = seconds(sw); end
                    startwait_s(li) = double(sw);
                end
                if isfield(ld, "waittime") && ~isempty(ld.waittime)
                    wt = ld.waittime; if isduration(wt), wt = seconds(wt); end
                    waittime_s(li) = double(wt);
                end
            end

            % Allocate full data arrays.
            data = cell(1, meta.totalScalar);
            dataStride = cell(1, nloops);
            dataDims = cell(1, nloops);
            for li = 1:nloops
                bd = npoints(end:-1:li);
                if isempty(bd), bd = 1; end
                if isscalar(bd), bd(2) = 1; end
                dataDims{li} = bd;
                dataStride{li} = [1 cumprod(bd(1:end-1))];
                for k = 1:meta.nScalarGet(li)
                    data{meta.offset0(li) + k} = nan(bd);
                end
            end

            % Precompute turbo plot layout.
            dispEntries = scanObj.disp;
            numDisp = numel(dispEntries);
            plotData = cell(numDisp, 1);
            pXL = zeros(1, numDisp);   % x-loop per display
            pYL = zeros(1, numDisp);   % y-loop (0 for 1D)
            pRL = zeros(1, numDisp);   % reset-loop (0 if none)
            pLR = zeros(1, numDisp);   % last seen reset-loop count
            pLI = zeros(1, numDisp);   % local data index within loop getchan
            pByLoop = cell(1, nloops); % disp indices grouped by data loop
            for k = 1:numDisp
                dc = double(dispEntries(k).channel);
                xL = double(meta.dataloop(dc));
                pXL(k) = xL;
                yL = 0;
                if double(dispEntries(k).dim) == 2 && xL < nloops
                    yL = xL + 1;
                end
                pYL(k) = yL;
                rL = xL + 1;
                if yL > 0
                    plotData{k} = nan(npoints(yL), npoints(xL));
                    rL = yL + 1;
                else
                    plotData{k} = nan(1, npoints(xL));
                end
                if rL <= nloops
                    pRL(k) = rL;
                    pLR(k) = 1;
                end
                pLI(k) = dc - double(meta.offset0(xL));
            end
            for li = 1:nloops
                pByLoop{li} = find(pXL == li);
            end

            % Temp save config.
            enableTemp = true;
            saveLI = double(scanObj.saveloop);
            if ~(isfinite(saveLI) && saveLI >= 1 && saveLI <= nloops && mod(saveLI, 1) == 0)
                error("measurementEngine:InvalidSaveLoop", "saveloop must be an integer in [1, %d].", nloops);
            end
            saveMinInterval_s = seconds(scanObj.saveMinInterval);
            if ~(isfinite(saveMinInterval_s) && saveMinInterval_s > 0)
                error("measurementEngine:InvalidSaveMinInterval", "saveMinInterval must be a finite, positive duration.");
            end
            lastTempSaveTic = [];

            % Set constants.
            rack.flush();
            if enableLog
                msg = "runTurboScanCore_ start name=" + scanObj.name + " loops=" + nloops;
                experimentContext.print(msg);
                logFcn(msg);
            end
            if ~isempty(scanObj.consts)
                consts = scanObj.consts;
                if ~isfield(consts, "set"), [consts.set] = deal(1); end
                m = [consts.set] == 1;
                if any(m)
                    sc = string({consts(m).setchan}); if isrow(sc), sc = sc.'; end
                    rack.rackSet(sc, double([consts(m).val]).');
                end
            end

            % Snapshot timing.
            snapInt_s = seconds(snapshotInterval);
            lastSnapTic = tic;

            % --- Main measurement loop ---
            stopped = false;
            count = ones(1, nloops);
            totpoints = prod(npoints);
            didLogSet = false;
            didLogGet = false;
            firstSnap = false;

            for ptIdx = 1:totpoints
                % Stop check
                if ~stopped && clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Periodic snapshot
                if toc(lastSnapTic) >= snapInt_s
                    send(engineToClient, struct("type", "turboSnapshot", "requestId", requestId, "count", count, "plotData", {plotData}));
                    lastSnapTic = tic;
                    if enableLog && ~firstSnap
                        firstSnap = true;
                        msg = "runTurboScanCore_ first turboSnapshot " + requestId;
                        experimentContext.print(msg);
                        logFcn(msg);
                    end
                end

                % Determine which loops need setting.
                if ptIdx == 1
                    loopsToSet = 1:nloops;
                else
                    idx = find(count > 1, 1, "first");
                    if isempty(idx), idx = nloops; end
                    loopsToSet = 1:idx;
                end

                for li = fliplr(loopsToSet)
                    if ~stopped && clientToEngine.QueueLength > 0
                        ctl = poll(clientToEngine);
                        if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                            stopped = true;
                        end
                    end
                    if stopped, break; end

                    setchans = setchansByLoop{li};
                    if isempty(setchans), continue; end

                    ld = scanObj.loops(li);
                    vals = nan(numel(setchans), 1);
                    if isfield(ld, "setchanranges") && ~isempty(ld.setchanranges) && iscell(ld.setchanranges)
                        nr = min(numel(setchans), numel(ld.setchanranges));
                        for k = 1:nr
                            r = ld.setchanranges{k};
                            if isempty(r), continue; end
                            if npoints(li) > 1 && numel(r) >= 2
                                vals(k) = r(1) + (r(2) - r(1)) * (count(li) - 1) / (npoints(li) - 1);
                            else
                                vals(k) = r(1);
                            end
                        end
                        vals(isnan(vals)) = count(li);
                    elseif isfield(ld, "rng") && ~isempty(ld.rng) && numel(ld.rng) >= 2
                        r = ld.rng;
                        if npoints(li) > 1
                            vals(:) = r(1) + (r(2) - r(1)) * (count(li) - 1) / (npoints(li) - 1);
                        else
                            vals(:) = r(1);
                        end
                    else
                        vals(:) = count(li);
                    end

                    if enableLog && ~didLogSet
                        didLogSet = true;
                        msg = "runTurboScanCore_ first rackSet loop=" + li;
                        experimentContext.print(msg);
                        logFcn(msg);
                    end
                    rack.rackSet(setchans, vals);

                    % Interruptible startwait
                    if count(li) == 1 && startwait_s(li) > 0
                        rem_ = startwait_s(li);
                        while rem_ > 0 && ~stopped
                            if clientToEngine.QueueLength > 0
                                ctl = poll(clientToEngine);
                                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                                    stopped = true; break;
                                end
                            end
                            s_ = min(0.05, rem_); pause(s_); rem_ = rem_ - s_;
                        end
                    end
                    if stopped, break; end

                    % Interruptible waittime
                    if waittime_s(li) > 0
                        rem_ = waittime_s(li);
                        while rem_ > 0 && ~stopped
                            if clientToEngine.QueueLength > 0
                                ctl = poll(clientToEngine);
                                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                                    stopped = true; break;
                                end
                            end
                            s_ = min(0.05, rem_); pause(s_); rem_ = rem_ - s_;
                        end
                    end
                end
                if stopped, break; end

                % Stop check after set
                if clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Determine which loops to read.
                if ptIdx == 1
                    loopsToRead = 1:nloops;
                else
                    idx = find(count < npoints, 1, "first");
                    if isempty(idx), idx = nloops; end
                    loopsToRead = 1:idx;
                end

                for li = loopsToRead
                    if ~stopped && clientToEngine.QueueLength > 0
                        ctl = poll(clientToEngine);
                        if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                            stopped = true;
                        end
                    end
                    if stopped, break; end

                    getchans = getchansByLoop{li};
                    if ~isempty(getchans) && meta.nScalarGet(li) > 0
                        if enableLog && ~didLogGet
                            didLogGet = true;
                            msg = "runTurboScanCore_ first rackGet loop=" + li;
                            experimentContext.print(msg);
                            logFcn(msg);
                        end
                        newdata = double(rack.rackGet(getchans));
                        newdata = newdata(:);

                        % Store in data arrays.
                        stride = dataStride{li};
                        subs = count(nloops:-1:li);
                        if numel(subs) < numel(dataDims{li})
                            subs(end+1:numel(dataDims{li})) = 1;
                        end
                        linIdx = 1 + sum((subs - 1) .* stride);
                        for k = 1:meta.nScalarGet(li)
                            data{meta.offset0(li) + k}(linIdx) = newdata(k);
                        end

                        % Reset plot arrays when outer loop resets.
                        for k = 1:numDisp
                            rL = pRL(k);
                            if rL > 0 && count(rL) ~= pLR(k)
                                plotData{k}(:) = NaN;
                                pLR(k) = count(rL);
                            end
                        end
                        % Fill plot data via direct indexing.
                        dIdxs = pByLoop{li};
                        for j = 1:numel(dIdxs)
                            k = dIdxs(j);
                            lI = pLI(k);
                            if lI >= 1 && lI <= numel(newdata)
                                if pYL(k) > 0
                                    plotData{k}(count(pYL(k)), count(pXL(k))) = newdata(lI);
                                else
                                    plotData{k}(count(pXL(k))) = newdata(lI);
                                end
                            end
                        end

                        % Snapshot at interval.
                        if toc(lastSnapTic) >= snapInt_s
                            send(engineToClient, struct("type", "turboSnapshot", "requestId", requestId, "count", count, "plotData", {plotData}));
                            lastSnapTic = tic;
                        end
                    end

                    % Temp save.
                    if enableTemp && li == saveLI
                        if isempty(lastTempSaveTic) || toc(lastTempSaveTic) >= saveMinInterval_s
                            send(engineToClient, struct("type", "tempData", "requestId", requestId, "count", count, "data", {data}));
                            lastTempSaveTic = tic;
                        end
                    end
                end

                % Stop check after read
                if ~stopped && clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Update counters.
                j = 1;
                while j <= numel(loopsToRead)
                    li = loopsToRead(j);
                    if count(li) < npoints(li)
                        count(li) = count(li) + 1;
                        break;
                    else
                        count(li) = 1;
                        j = j + 1;
                    end
                end
            end

            % Final snapshot.
            send(engineToClient, struct("type", "turboSnapshot", "requestId", requestId, "count", count, "plotData", {plotData}));
        end

        function [data, stopped] = runSafeScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, logFcn)
            % Safe scan loop: send safePoint after each read, wait for ack/stop.
            enableLog = ~isempty(logFcn) && isa(logFcn, "function_handle");
            meta = measurementEngine.computeScanMeta_(scanObj);
            nloops = meta.nloops;
            npoints = meta.npoints;

            % Precompute per-loop channels and wait durations.
            setchansByLoop = cell(1, nloops);
            getchansByLoop = cell(1, nloops);
            startwait_s = zeros(1, nloops);
            waittime_s = zeros(1, nloops);
            for li = 1:nloops
                ld = scanObj.loops(li);
                setchansByLoop{li} = string(ld.setchan(:));
                getchansByLoop{li} = string(ld.getchan(:));
                if isfield(ld, "startwait") && ~isempty(ld.startwait)
                    sw = ld.startwait; if isduration(sw), sw = seconds(sw); end
                    startwait_s(li) = double(sw);
                end
                if isfield(ld, "waittime") && ~isempty(ld.waittime)
                    wt = ld.waittime; if isduration(wt), wt = seconds(wt); end
                    waittime_s(li) = double(wt);
                end
            end

            % Allocate data arrays.
            data = cell(1, meta.totalScalar);
            dataStride = cell(1, nloops);
            dataDims = cell(1, nloops);
            for li = 1:nloops
                bd = npoints(end:-1:li);
                if isempty(bd), bd = 1; end
                if isscalar(bd), bd(2) = 1; end
                dataDims{li} = bd;
                dataStride{li} = [1 cumprod(bd(1:end-1))];
                for k = 1:meta.nScalarGet(li)
                    data{meta.offset0(li) + k} = nan(bd);
                end
            end

            % Precompute display info for safePoint plot values.
            dispEntries = scanObj.disp;
            numDisp = numel(dispEntries);
            dispDL = zeros(1, numDisp);  % dataloop per display channel
            dispLI = zeros(1, numDisp);  % local index within loop get data
            for k = 1:numDisp
                dc = double(dispEntries(k).channel);
                dispDL(k) = double(meta.dataloop(dc));
                dispLI(k) = dc - double(meta.offset0(dispDL(k)));
            end

            % Temp save config.
            enableTemp = true;
            saveLI = double(scanObj.saveloop);
            if ~(isfinite(saveLI) && saveLI >= 1 && saveLI <= nloops && mod(saveLI, 1) == 0)
                error("measurementEngine:InvalidSaveLoop", "saveloop must be an integer in [1, %d].", nloops);
            end
            saveMinInterval_s = seconds(scanObj.saveMinInterval);
            if ~(isfinite(saveMinInterval_s) && saveMinInterval_s > 0)
                error("measurementEngine:InvalidSaveMinInterval", "saveMinInterval must be a finite, positive duration.");
            end
            lastTempSaveTic = [];

            % Set constants.
            rack.flush();
            if enableLog
                msg = "runSafeScanCore_ start name=" + scanObj.name + " loops=" + nloops;
                experimentContext.print(msg);
                logFcn(msg);
            end
            if ~isempty(scanObj.consts)
                consts = scanObj.consts;
                if ~isfield(consts, "set"), [consts.set] = deal(1); end
                m = [consts.set] == 1;
                if any(m)
                    sc = string({consts(m).setchan}); if isrow(sc), sc = sc.'; end
                    rack.rackSet(sc, double([consts(m).val]).');
                end
            end

            % --- Main loop ---
            stopped = false;
            count = ones(1, nloops);
            totpoints = prod(npoints);
            didLogSet = false;
            didLogGet = false;
            firstSafe = false;

            for ptIdx = 1:totpoints
                % Stop check
                if ~stopped && clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Determine which loops to set.
                if ptIdx == 1
                    loopsToSet = 1:nloops;
                else
                    idx = find(count > 1, 1, "first");
                    if isempty(idx), idx = nloops; end
                    loopsToSet = 1:idx;
                end

                for li = fliplr(loopsToSet)
                    if ~stopped && clientToEngine.QueueLength > 0
                        ctl = poll(clientToEngine);
                        if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                            stopped = true;
                        end
                    end
                    if stopped, break; end

                    setchans = setchansByLoop{li};
                    if isempty(setchans), continue; end

                    ld = scanObj.loops(li);
                    vals = nan(numel(setchans), 1);
                    if isfield(ld, "setchanranges") && ~isempty(ld.setchanranges) && iscell(ld.setchanranges)
                        nr = min(numel(setchans), numel(ld.setchanranges));
                        for k = 1:nr
                            r = ld.setchanranges{k};
                            if isempty(r), continue; end
                            if npoints(li) > 1 && numel(r) >= 2
                                vals(k) = r(1) + (r(2) - r(1)) * (count(li) - 1) / (npoints(li) - 1);
                            else
                                vals(k) = r(1);
                            end
                        end
                        vals(isnan(vals)) = count(li);
                    elseif isfield(ld, "rng") && ~isempty(ld.rng) && numel(ld.rng) >= 2
                        r = ld.rng;
                        if npoints(li) > 1
                            vals(:) = r(1) + (r(2) - r(1)) * (count(li) - 1) / (npoints(li) - 1);
                        else
                            vals(:) = r(1);
                        end
                    else
                        vals(:) = count(li);
                    end

                    if enableLog && ~didLogSet
                        didLogSet = true;
                        msg = "runSafeScanCore_ first rackSet loop=" + li;
                        experimentContext.print(msg);
                        logFcn(msg);
                    end
                    rack.rackSet(setchans, vals);

                    % Interruptible startwait
                    if count(li) == 1 && startwait_s(li) > 0
                        rem_ = startwait_s(li);
                        while rem_ > 0 && ~stopped
                            if clientToEngine.QueueLength > 0
                                ctl = poll(clientToEngine);
                                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                                    stopped = true; break;
                                end
                            end
                            s_ = min(0.05, rem_); pause(s_); rem_ = rem_ - s_;
                        end
                    end
                    if stopped, break; end

                    % Interruptible waittime
                    if waittime_s(li) > 0
                        rem_ = waittime_s(li);
                        while rem_ > 0 && ~stopped
                            if clientToEngine.QueueLength > 0
                                ctl = poll(clientToEngine);
                                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                                    stopped = true; break;
                                end
                            end
                            s_ = min(0.05, rem_); pause(s_); rem_ = rem_ - s_;
                        end
                    end
                end
                if stopped, break; end

                % Stop check after set
                if clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Determine which loops to read.
                if ptIdx == 1
                    loopsToRead = 1:nloops;
                else
                    idx = find(count < npoints, 1, "first");
                    if isempty(idx), idx = nloops; end
                    loopsToRead = 1:idx;
                end

                for li = loopsToRead
                    if ~stopped && clientToEngine.QueueLength > 0
                        ctl = poll(clientToEngine);
                        if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                            stopped = true;
                        end
                    end
                    if stopped, break; end

                    getchans = getchansByLoop{li};
                    if ~isempty(getchans) && meta.nScalarGet(li) > 0
                        if enableLog && ~didLogGet
                            didLogGet = true;
                            msg = "runSafeScanCore_ first rackGet loop=" + li;
                            experimentContext.print(msg);
                            logFcn(msg);
                        end
                        newdata = double(rack.rackGet(getchans));
                        newdata = newdata(:);

                        % Store in data arrays.
                        stride = dataStride{li};
                        subs = count(nloops:-1:li);
                        if numel(subs) < numel(dataDims{li})
                            subs(end+1:numel(dataDims{li})) = 1;
                        end
                        linIdx = 1 + sum((subs - 1) .* stride);
                        for k = 1:meta.nScalarGet(li)
                            data{meta.offset0(li) + k}(linIdx) = newdata(k);
                        end

                        % Send safePoint with plot values.
                        plotValues = nan(numDisp, 1);
                        for k = 1:numDisp
                            if dispDL(k) == li
                                plotValues(k) = newdata(dispLI(k));
                            end
                        end
                        send(engineToClient, struct("type", "safePoint", "requestId", requestId, "loopIdx", li, "count", count, "plotValues", plotValues));
                        if enableLog && ~firstSafe
                            firstSafe = true;
                            msg = "runSafeScanCore_ first safePoint " + requestId;
                            experimentContext.print(msg);
                            logFcn(msg);
                        end

                        % Wait for ack or stop: record queue length, poll that many, handle each.
                        ackTimeout = datetime("now") + minutes(5);
                        while ~stopped
                            if clientToEngine.QueueLength == 0
                                assert(datetime("now") < ackTimeout, "measurementEngine:AckTimeout", "Timed out waiting for ack/stop.");
                                pause(0.001);
                                continue;
                            end
                            n = clientToEngine.QueueLength;
                            gotAck = false;
                            for qi = 1:n
                                ctl = poll(clientToEngine);
                                if ~isstruct(ctl) || ~isfield(ctl, "type"), continue; end
                                if ctl.type == "ack"
                                    gotAck = true;
                                elseif ctl.type == "stop"
                                    stopped = true;
                                end
                            end
                            if gotAck || stopped, break; end
                        end
                        if stopped, break; end
                    end

                    % Temp save.
                    if enableTemp && li == saveLI
                        if isempty(lastTempSaveTic) || toc(lastTempSaveTic) >= saveMinInterval_s
                            send(engineToClient, struct("type", "tempData", "requestId", requestId, "count", count, "data", {data}));
                            lastTempSaveTic = tic;
                        end
                    end
                end

                % Stop check after read
                if ~stopped && clientToEngine.QueueLength > 0
                    ctl = poll(clientToEngine);
                    if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                        stopped = true;
                    end
                end
                if stopped, break; end

                % Update counters.
                j = 1;
                while j <= numel(loopsToRead)
                    li = loopsToRead(j);
                    if count(li) < npoints(li)
                        count(li) = count(li) + 1;
                        break;
                    else
                        count(li) = 1;
                        j = j + 1;
                    end
                end
            end
        end
    end

    methods (Static)
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
                    pause(0.01);
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
                                [data, ~] = measurementEngine.runSafeScanCore_(rack, currentRunScanObj, clientToEngine, engineToClient, currentRunRequestId, logCore);
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
                                [data, ~, ~] = measurementEngine.runTurboScanCore_(rack, currentRunScanObj, clientToEngine, engineToClient, currentRunRequestId, snapshotInterval, logCore);
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
                    pause(0.01);
                end
            end

        end

        function varargout = workerTaskMain_(workerFprintfQueue, requestedBy, fcn, varargin)
            if isempty(workerFprintfQueue) || ~isa(workerFprintfQueue, "parallel.pool.DataQueue")
                error("measurementEngine:MissingFprintfQueue", "workerTaskMain_ requires parallel.pool.DataQueue relay.");
            end
            if ~isa(fcn, "function_handle")
                error("measurementEngine:InvalidWorkerSpawnFcn", "workerTaskMain_ expects a function_handle.");
            end

            requestedBy = string(requestedBy);
            if strlength(requestedBy) == 0
                requestedBy = "instrument";
            end
            experimentContext.setFprintfRelay(workerFprintfQueue, requestedBy);

            if nargout > 0
                [varargout{1:nargout}] = fcn(varargin{:});
            else
                fcn(varargin{:});
            end
        end
    end
end

