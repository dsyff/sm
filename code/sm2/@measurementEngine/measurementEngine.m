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
        slack_notification_settings (1, 1) struct = struct("webhook", "", "api_token", "", "channel_id", "", "user_id", "", "account_email", "")

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

        isScanInProgress (1, 1) logical = false
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
                options.slack_notification_settings (1, 1) struct = struct("webhook", "", "api_token", "", "channel_id", "", "user_id", "", "account_email", "")
            end

            obj = measurementEngine(instrumentRackRecipe(), ...
                internalDeferInit = true, ...
                verboseClient = options.verboseClient, ...
                clientLogFile = options.clientLogFile, ...
                experimentRootPath = options.experimentRootPath, ...
                slack_notification_settings = options.slack_notification_settings);
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
                options.slack_notification_settings (1, 1) struct = struct("webhook", "", "api_token", "", "channel_id", "", "user_id", "", "account_email", "")
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
            slackSettings = options.slack_notification_settings;
            if ~isfield(slackSettings, "webhook")
                slackSettings.webhook = "";
            end
            if ~isfield(slackSettings, "api_token")
                slackSettings.api_token = "";
            end
            if ~isfield(slackSettings, "channel_id")
                slackSettings.channel_id = "";
            end
            if ~isfield(slackSettings, "user_id")
                slackSettings.user_id = "";
            end
            if ~isfield(slackSettings, "account_email")
                slackSettings.account_email = "";
            end
            slackSettings.webhook = string(slackSettings.webhook);
            slackSettings.api_token = string(slackSettings.api_token);
            slackSettings.channel_id = string(slackSettings.channel_id);
            slackSettings.user_id = string(slackSettings.user_id);
            slackSettings.account_email = string(slackSettings.account_email);
            if ~isscalar(slackSettings.webhook)
                error("measurementEngine:InvalidSlackNotificationSettings", ...
                    "slack_notification_settings.webhook must be a scalar string.");
            end
            if ~isscalar(slackSettings.api_token)
                error("measurementEngine:InvalidSlackNotificationSettings", ...
                    "slack_notification_settings.api_token must be a scalar string.");
            end
            if ~isscalar(slackSettings.channel_id)
                error("measurementEngine:InvalidSlackNotificationSettings", ...
                    "slack_notification_settings.channel_id must be a scalar string.");
            end
            if ~isscalar(slackSettings.user_id)
                error("measurementEngine:InvalidSlackNotificationSettings", ...
                    "slack_notification_settings.user_id must be a scalar string.");
            end
            if ~isscalar(slackSettings.account_email)
                error("measurementEngine:InvalidSlackNotificationSettings", ...
                    "slack_notification_settings.account_email must be a scalar string.");
            end
            obj.slack_notification_settings = slackSettings;

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

        function info = getRackInfoForEditing(obj)
            if obj.constructionMode == "rack"
                info = obj.rackLocal.getRackInfoForEditing();
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "rackEditInfo", ...
                "requestId", requestId));

            reply = obj.waitForEngineReply_(requestId, "rackEditInfoDone", seconds(20));
            if isfield(reply, "ok") && ~logical(reply.ok)
                obj.throwRemoteError_(reply);
            end
            info = reply.info;
        end

        function applyRackEditPatch(obj, patch)
            arguments
                obj
                patch (1, 1) instrumentRackEditPatch
            end

            if obj.isScanInProgress
                error("measurementEngine:ScanActive", "Cannot apply rack edits while a scan is in progress.");
            end
            if patch.isEmpty()
                return;
            end

            if obj.constructionMode == "rack"
                obj.rackLocal.applyRackEditPatch(patch);
                return;
            end

            requestId = obj.nextRequestId_();
            obj.safeSendToEngine_(struct( ...
                "type", "rackEditPatch", ...
                "requestId", requestId, ...
                "patch", patch));

            reply = obj.waitForEngineReply_(requestId, "rackEditPatchDone", seconds(20));
            if isfield(reply, "ok") && ~logical(reply.ok)
                obj.throwRemoteError_(reply);
            end
        end

        function [channelNames, channelSizes] = getChannelMetadata(obj)
            channelNames = obj.channelFriendlyNames;
            channelSizes = obj.channelSizes;
            if obj.constructionMode == "rack"
                channelNames = obj.rackLocal.channelTable.channelFriendlyNames(:);
                channelSizes = double(obj.rackLocal.channelTable.channelSizes(:));
            end
        end

        function [dataOut, runMetadata] = run(obj, scan, filename, mode)
            arguments
                obj
                scan
                filename (1, 1) string = ""
                mode (1, 1) string {mustBeMember(mode, ["safe", "turbo"])} = "safe"
            end

            runMetadata = struct("filename", "", "pngFile", "", "pngSaved", false, "duration", seconds(NaN), "isComplete", false);
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
                [dataOut, scanForSave] = obj.runLocal_(scanObj, filename);
            else
                [dataOut, scanForSave] = obj.runOnWorker_(scanObj, filename, mode);
            end

            if autoRun
                try
                    smrunUpdateGlobalState("engine", smrunIncrement(runToUse));
                catch
                end
            end

            runMetadata.filename = filename;
            [runPath, runBase] = fileparts(filename);
            if strlength(runBase) == 0
                runMetadata.pngFile = filename + ".png";
            elseif strlength(runPath) == 0
                runMetadata.pngFile = runBase + ".png";
            else
                runMetadata.pngFile = fullfile(runPath, runBase + ".png");
            end
            runMetadata.pngSaved = isfile(runMetadata.pngFile);
            if isfield(scanForSave, "duration") && isduration(scanForSave.duration)
                runMetadata.duration = scanForSave.duration;
            end
            if isfield(scanForSave, "isComplete")
                runMetadata.isComplete = logical(scanForSave.isComplete);
            end
        end

        function cacheSlackNotificationUserId(obj, accountEmail, userId)
            arguments
                obj
                accountEmail (1, 1) string
                userId (1, 1) string
            end
            accountEmail = strip(accountEmail);
            userId = strip(userId);
            if strlength(accountEmail) == 0 || strlength(userId) == 0
                return;
            end
            obj.slack_notification_settings.account_email = accountEmail;
            obj.slack_notification_settings.user_id = userId;
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
                                obj.throwRemoteError_(msg);
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
                pause(1E-6);
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

        function reply = waitForEngineReply_(obj, requestId, expectedType, timeout)
            if nargin < 4 || isempty(timeout)
                timeout = hours(3);
            end
            if ~isduration(timeout)
                timeout = seconds(double(timeout));
            end
            if ~(isscalar(timeout) && isfinite(seconds(timeout)) && timeout > seconds(0))
                error("measurementEngine:InvalidTimeout", "waitForEngineReply_ timeout must be a finite, positive duration.");
            end
            startTime = datetime("now");
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
                pause(1E-6);
            end
        end

        function throwRemoteError_(~, reply)
            if isfield(reply, "error") && ~isempty(reply.error)
                err = reply.error;
                if isstruct(err) && isfield(err, "message")
                    msgText = char(string(err.message));
                    experimentContext.print("Engine worker error: %s", msgText);

                    idText = "measurementEngine:RemoteError";
                    if isfield(err, "identifier") && strlength(string(err.identifier)) > 0
                        idText = char(string(err.identifier));
                    end

                    if isfield(err, "stack") && ~isempty(err.stack)
                        errStruct = struct();
                        errStruct.identifier = idText;
                        errStruct.message = msgText;
                        errStruct.stack = err.stack;
                        error(errStruct);
                    end

                    error(idText, "%s", msgText);
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

        function [dataOut, scanForSave] = runLocal_(obj, scanObj, filename)
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

        function [dataOut, scanForSave] = runOnWorker_(obj, scanObj, filename, mode)
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
            scanForSave.isComplete = false;
            [figHandle, plotState] = obj.initLiveFigure_(scanObj, scanForSave);

            pendingClose = false;
            lastCount = ones(1, plotState.nloops);
            obj.isScanInProgress = true;

            set(figHandle, "CurrentCharacter", char(0));
            set(figHandle, "CloseRequestFcn", @onClose);

            function onClose(~, ~)
                if ~obj.isScanInProgress
                    try
                        set(figHandle, "CloseRequestFcn", "closereq");
                        delete(figHandle);
                    catch
                    end
                    return;
                end
                selection = questdlg("Stop the scan and close this figure?", "Closing", "Stop", "Cancel", "Cancel");
                if selection ~= "Stop"
                    return;
                end
                obj.isScanInProgress = false;
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
            try
                [dataOut, stopped] = measurementEngine.runScanCore_(rack, scanObj, @onRead, figHandle, duration.empty, [], @onTemp, [], @() obj.isScanInProgress);
            catch ME
                obj.isScanInProgress = false;
                rethrow(ME);
            end
            scanEnd = datetime("now");
            scanForSave.startTime = scanStart;
            scanForSave.endTime = scanEnd;
            scanForSave.duration = scanEnd - scanStart;
            scanForSave.isComplete = ~stopped;
            obj.isScanInProgress = false;
        end

        [dataOut, scanForSave, figHandle, pendingClose] = runWorkerCore_(obj, scanObj, tempFile)
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

                isTwoDPlot = dim == 2 && xLoop < meta.nloops;
                if isTwoDPlot
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
                    if ~isTwoDPlot
                        ylabel(strrep(chName, "_", "\_"));
                    end
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

        saveFinal_(obj, filename, scanForSave, data, figHandle)
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

        rack = buildRackFromRecipe_(recipe, spawnOnClientFcn)
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

        [data, stopped] = runScanCore_(rack, scanObj, onRead, figHandle, snapshotInterval, onSnapshot, onTemp, logFcn, isScanInProgressFcn)
        stopped = waitWithStop_(waitDuration, figHandle, isScanInProgressFcn)
        [data, plotData, stopped] = runTurboScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, snapshotInterval, logFcn)
        [data, stopped] = runSafeScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, logFcn)
    end

    methods (Static)
        engineWorkerMain_(engineToClient, recipe, workerFprintfQueue, experimentRootPath, options)
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

