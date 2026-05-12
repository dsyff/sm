function [dataOut, scanForSave, figHandle, pendingClose] = runWorkerCore_(obj, scanObj, tempFile)
    % Runs a scan on the engine worker and keeps the save copy on the client.

    scanForSave = scanObj.toSaveStruct();
    scanForSave.isComplete = false;

    [figHandle, plotState] = obj.initLiveFigure_(scanObj, scanForSave);
    layout = measurementEngine.computeFlatDataLayout_(scanObj);
    dataFlat = measurementEngine.initializeFlatData_(layout);
    lastCount = ones(1, plotState.nloops);

    saveLI = double(scanObj.saveloop);
    if ~(isfinite(saveLI) && saveLI >= 1 && mod(saveLI, 1) == 0)
        error("measurementEngine:InvalidSaveLoop", "saveloop must be a positive integer loop index.");
    end
    saveMinInterval_s = seconds(scanObj.saveMinInterval);
    if ~(isfinite(saveMinInterval_s) && saveMinInterval_s > 0)
        error("measurementEngine:InvalidSaveMinInterval", "saveMinInterval must be a finite, positive duration.");
    end

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

    function applyDataDirty(channelIdx, flatIdx, values)
        channelIdx = double(channelIdx(:));
        flatIdx = double(flatIdx(:));
        values = double(values(:));
        if isempty(values)
            return;
        end
        chans = unique(channelIdx(:).');
        for ch = chans
            mask = channelIdx == ch;
            dataFlat{ch}(flatIdx(mask)) = values(mask);
        end
    end

    function applyTurboPlotDirty(msg)
        if isempty(plotState.disp)
            return;
        end
        if isfield(msg, "resetDispIdx")
            resetDispIdx = unique(double(msg.resetDispIdx(:))).';
            for k = resetDispIdx
                if k < 1 || k > numel(plotState.disp)
                    continue;
                end
                if plotState.disp(k).dim == 2 && plotState.yLoop(k) > 0
                    plotState.twoDData{k}(:) = NaN;
                    set(plotState.handles(k), "CData", plotState.twoDData{k});
                else
                    plotState.oneDData{k}(:) = NaN;
                    set(plotState.handles(k), "YData", plotState.oneDData{k});
                end
            end
        end

        if ~isfield(msg, "plotDispIdx") || isempty(msg.plotDispIdx)
            return;
        end
        plotDispIdx = double(msg.plotDispIdx(:));
        plotX = double(msg.plotX(:));
        plotY = double(msg.plotY(:));
        plotValues = double(msg.plotValues(:));
        for k = unique(plotDispIdx(:).')
            if k < 1 || k > numel(plotState.disp)
                continue;
            end
            mask = plotDispIdx == k;
            if plotState.disp(k).dim == 2 && plotState.yLoop(k) > 0
                z = plotState.twoDData{k};
                lin = sub2ind(size(z), plotY(mask), plotX(mask));
                z(lin) = plotValues(mask);
                plotState.twoDData{k} = z;
                set(plotState.handles(k), "CData", z);
            else
                y = plotState.oneDData{k};
                y(plotX(mask)) = plotValues(mask);
                plotState.oneDData{k} = y;
                set(plotState.handles(k), "YData", y);
            end
        end
    end

    lastTempSaveTic = [];
    function maybeSaveTemp(saveLoopHit)
        if ~saveLoopHit || strlength(tempFile) == 0
            return;
        end
        if ~isempty(lastTempSaveTic) && toc(lastTempSaveTic) < saveMinInterval_s
            return;
        end
        try
            savePayload = struct();
            savePayload.scan = scanForSave;
            savePayload.data = measurementEngine.reshapeFlatData_(dataFlat, layout);
            save(tempFile, "-struct", "savePayload");
            lastTempSaveTic = tic;
        catch
        end
    end

    try
        runId = obj.nextRequestId_();
        scanStart = datetime("now");
        scanForSave.startTime = scanStart;
        scanObj = obj.prepareScanConstants_(scanObj);
        scanForSave.consts = scanObj.consts;
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

        gotAnyData = false;
        nextWaitLogTime = datetime("now") + seconds(2);
        sentFirstAck = false;
        lastUiPumpTic = tic;

        done = false;
        runComplete = false;
        while ~done
            checkEsc();

            if ~isempty(obj.engineToClientBacklog)
                backlog = obj.engineToClientBacklog;
                obj.engineToClientBacklog = cell(1, 0);
                for i = 1:numel(backlog)
                    handleEngineMessage(backlog{i});
                    if done
                        break;
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
                handleEngineMessage(poll(obj.engineToClient));
                if done
                    break;
                end
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

            if ~obj.isScanInProgress && ~stopSent
                obj.safeSendToEngine_(struct("type", "stop", "requestId", runId));
                stopSent = true;
            end

            fut = obj.engineWorkerFuture_();
            if ~isempty(fut) && isprop(fut, "State") && fut.State ~= "running"
                error("measurementEngine:EngineWorkerFailed", "Engine worker failed during run. State: %s", fut.State);
            end

            pause(1E-6);
        end

        scanEnd = datetime("now");
        scanForSave.startTime = scanStart;
        scanForSave.endTime = scanEnd;
        scanForSave.duration = scanEnd - scanStart;
        scanForSave.isComplete = runComplete;
        dataOut = measurementEngine.reshapeFlatData_(dataFlat, layout);
        obj.isScanInProgress = false;
    catch ME
        obj.isScanInProgress = false;
        rethrow(ME);
    end

    function handleEngineMessage(msg)
        if ~isstruct(msg) || ~isfield(msg, "type")
            return;
        end

        msgType = msg.type;
        if msgType == "parfeval"
            obj.handleEngineToClientMessage_(msg);
            return;
        end

        if ~isfield(msg, "requestId")
            return;
        end
        if msg.requestId ~= runId
            obj.engineToClientBacklog{end+1} = msg;
            return;
        end

        if msgType == "safePoint"
            if ~gotAnyData
                gotAnyData = true;
                obj.logClient_("received first safePoint " + runId);
            end
            if isfield(msg, "channelIdx")
                applyDataDirty(msg.channelIdx, msg.flatIdx, msg.values);
            end
            loopIdx = double(msg.loopIdx);
            count = double(msg.count(:)).';
            plotValues = double(msg.plotValues(:));
            [plotState, lastCount] = obj.applySafePlotUpdate_(plotState, lastCount, loopIdx, count, plotValues);
            maybeSaveTemp(loopIdx == saveLI);
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
            lastUiPumpTic = tic;
            return;
        end

        if msgType == "turboDirty"
            if ~gotAnyData
                gotAnyData = true;
                obj.logClient_("received first turboDirty " + runId);
            end
            applyDataDirty(msg.channelIdx, msg.flatIdx, msg.values);
            applyTurboPlotDirty(msg);
            maybeSaveTemp(isfield(msg, "saveLoopHit") && logical(msg.saveLoopHit));
            drawnow limitrate;
            checkEsc();
            if isfield(msg, "seq")
                obj.safeSendToEngine_(struct("type", "turboReady", "requestId", runId, "seq", msg.seq));
            end
            lastUiPumpTic = tic;
            return;
        end

        if msgType == "runDone"
            if isfield(msg, "ok") && ~logical(msg.ok)
                obj.throwRemoteError_(msg);
            end
            runComplete = isfield(msg, "completed") && logical(msg.completed);
            obj.logClient_("runDone ok " + runId);
            done = true;
        end
    end
end

