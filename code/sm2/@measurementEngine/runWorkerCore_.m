function [dataOut, scanForSave, figHandle, pendingClose] = runWorkerCore_(obj, scanObj, tempFile)
    % Runs a scan on the engine worker and updates GUI on the client.

    scanForSave = scanObj.toSaveStruct();
    scanForSave.isComplete = false;

    [figHandle, plotState] = obj.initLiveFigure_(scanObj, scanForSave);
    stopSent = false;
    pendingClose = false;
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
            obj.isScanInProgress = false;
        end
    end

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

    try
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
        lastUiPumpTic = tic;

        done = false;
        runComplete = false;
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
                    if toc(lastUiPumpTic) >= 0.05
                        drawnow;
                        checkEsc();
                        lastUiPumpTic = tic;
                    end
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
                        if ~obj.isScanInProgress
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
                        runComplete = isfield(msg, "completed") && logical(msg.completed);
                        done = true;
                        continue;
                    end
                end
            end

            qlen = obj.engineToClient.QueueLength;

            for q = 1:qlen
                if toc(lastUiPumpTic) >= 0.05
                    drawnow;
                    checkEsc();
                    lastUiPumpTic = tic;
                end
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
                    if ~obj.isScanInProgress
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
                    runComplete = isfield(msg, "completed") && logical(msg.completed);
                    obj.logClient_("runDone ok " + runId);
                    done = true;
                    continue;
                end
            end

            if hasLatestPlotData
                obj.applyTurboPlotUpdate_(plotState, latestPlotData);
                drawnow limitrate;
                checkEsc();
                lastUiPumpTic = tic;
            end
            if hasLatestTempData
                saveTemp(latestTempData);
            end

            if toc(lastUiPumpTic) >= 0.05
                drawnow;
                checkEsc();
                lastUiPumpTic = tic;
            end

            if done
                break;
            end

            if ~gotAnyData && obj.verboseClient && datetime("now") >= nextWaitLogTime
                obj.logClient_("waiting for worker messages " + runId + " qlen=" + obj.engineToClient.QueueLength);
                nextWaitLogTime = datetime("now") + seconds(2);
            end

            if ~obj.isScanInProgress
                if ~stopSent
                    obj.safeSendToEngine_(struct("type", "stop", "requestId", runId));
                    stopSent = true;
                end
            end

            fut = obj.engineWorkerFuture_();
            if ~isempty(fut) && isprop(fut, "State") && fut.State ~= "running"
                error("measurementEngine:EngineWorkerFailed", "Engine worker failed during run. State: %s", fut.State);
            end

            pause(1E-6);
        end

        % If we exited early in turbo mode, drain any remaining snapshots and
        % update the GUI once more before saving/export.
        if ~obj.isScanInProgress && scanObj.mode == "turbo"
            qlen = obj.engineToClient.QueueLength;
            latestPlotData = {};
            hasLatestPlotData = false;
            latestTempData = {};
            hasLatestTempData = false;
            for q = 1:qlen
                if toc(lastUiPumpTic) >= 0.05
                    drawnow;
                    checkEsc();
                    lastUiPumpTic = tic;
                end
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
                lastUiPumpTic = tic;
            end
            if hasLatestTempData
                saveTemp(latestTempData);
            end
        end

        scanEnd = datetime("now");
        scanForSave.startTime = scanStart;
        scanForSave.endTime = scanEnd;
        scanForSave.duration = scanEnd - scanStart;
        scanForSave.isComplete = runComplete;
        obj.isScanInProgress = false;
    catch ME
        obj.isScanInProgress = false;
        rethrow(ME);
    end
end

