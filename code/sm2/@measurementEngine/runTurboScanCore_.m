function [data, stopped] = runTurboScanCore_(rack, scanObj, clientToEngine, engineToClient, requestId, snapshotInterval, logFcn)
    % Turbo scan loop: acquire continuously, send compact dirty batches when the client is ready.
    enableLog = ~isempty(logFcn) && isa(logFcn, "function_handle");
    meta = measurementEngine.computeScanMeta_(scanObj);
    layout = measurementEngine.computeFlatDataLayout_(scanObj);
    nloops = meta.nloops;
    npoints = meta.npoints;

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

    data = measurementEngine.initializeFlatData_(layout);

    dispEntries = scanObj.disp;
    numDisp = numel(dispEntries);
    pXL = zeros(1, numDisp);
    pYL = zeros(1, numDisp);
    pRL = zeros(1, numDisp);
    pLR = ones(1, numDisp);
    pLI = zeros(1, numDisp);
    pByLoop = cell(1, nloops);
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
            rL = yL + 1;
        end
        if rL <= nloops
            pRL(k) = rL;
        end
        pLI(k) = dc - double(meta.offset0(xL));
    end
    for li = 1:nloops
        pByLoop{li} = find(pXL == li);
    end

    saveLI = double(scanObj.saveloop);
    if ~(isfinite(saveLI) && saveLI >= 1 && mod(saveLI, 1) == 0)
        error("measurementEngine:InvalidSaveLoop", "saveloop must be a positive integer loop index.");
    end

    stopped = false;
    rack.flush();
    if enableLog
        msg = "runTurboScanCore_ start name=" + scanObj.name + " loops=" + nloops;
        experimentContext.print(msg);
        logFcn(msg);
    end

    snapInt_s = seconds(snapshotInterval);
    lastSnapTic = tic;
    updateInFlight = false;
    inFlightSeq = 0;
    nextSeq = 0;

    dirtyCap = 4096;
    dirtyN = 0;
    dirtyChannelIdx = zeros(dirtyCap, 1);
    dirtyFlatIdx = zeros(dirtyCap, 1);
    dirtyValues = zeros(dirtyCap, 1);
    dirtySaveLoopHit = false;

    plotCap = 2048;
    plotN = 0;
    plotDispIdx = zeros(plotCap, 1);
    plotX = zeros(plotCap, 1);
    plotY = zeros(plotCap, 1);
    plotValues = zeros(plotCap, 1);

    resetCap = 64;
    resetN = 0;
    resetDispIdx = zeros(resetCap, 1);

    count = ones(1, nloops);
    totpoints = prod(npoints);
    didLogSet = false;
    didLogGet = false;
    firstDirty = false;

    for ptIdx = 1:totpoints
        pollControls();
        if stopped, break; end

        if toc(lastSnapTic) >= snapInt_s
            flushDirty(false);
        end

        if ptIdx == 1
            loopsToSet = 1:nloops;
        else
            idx = find(count > 1, 1, "first");
            if isempty(idx), idx = nloops; end
            loopsToSet = 1:idx;
        end

        batchSetChans = string.empty(0, 1);
        batchSetVals = double.empty(0, 1);
        for li = fliplr(loopsToSet)
            pollControls();
            if stopped
                if ~isempty(batchSetChans)
                    if enableLog && ~didLogSet
                        didLogSet = true;
                        msg = "runTurboScanCore_ first rackSet n=" + numel(batchSetChans);
                        experimentContext.print(msg);
                        logFcn(msg);
                    end
                    stopped = rackSetWithStop(batchSetChans, batchSetVals, stopped);
                    batchSetChans = string.empty(0, 1);
                    batchSetVals = double.empty(0, 1);
                end
                break;
            end

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

            if isempty(batchSetChans)
                batchSetChans = setchans;
                batchSetVals = vals;
            else
                [isDup, dupIdx] = ismember(setchans, batchSetChans);
                if any(isDup)
                    batchSetVals(dupIdx(isDup)) = vals(isDup);
                end
                if any(~isDup)
                    batchSetChans = [batchSetChans; setchans(~isDup)];
                    batchSetVals = [batchSetVals; vals(~isDup)];
                end
            end

            if (count(li) == 1 && startwait_s(li) > 0) || waittime_s(li) > 0
                if enableLog && ~didLogSet
                    didLogSet = true;
                    msg = "runTurboScanCore_ first rackSet n=" + numel(batchSetChans);
                    experimentContext.print(msg);
                    logFcn(msg);
                end
                stopped = rackSetWithStop(batchSetChans, batchSetVals, stopped);
                batchSetChans = string.empty(0, 1);
                batchSetVals = double.empty(0, 1);
                if stopped, break; end

                if count(li) == 1 && startwait_s(li) > 0
                    interruptiblePause(startwait_s(li));
                end
                if stopped, break; end

                if waittime_s(li) > 0
                    interruptiblePause(waittime_s(li));
                end
            end
        end
        if ~isempty(batchSetChans)
            if enableLog && ~didLogSet
                didLogSet = true;
                msg = "runTurboScanCore_ first rackSet n=" + numel(batchSetChans);
                experimentContext.print(msg);
                logFcn(msg);
            end
            stopped = rackSetWithStop(batchSetChans, batchSetVals, stopped);
        end
        if stopped, break; end

        pollControls();
        if stopped, break; end

        if ptIdx == 1
            loopsToRead = 1:nloops;
        else
            idx = find(count < npoints, 1, "first");
            if isempty(idx), idx = nloops; end
            loopsToRead = 1:idx;
        end

        for li = loopsToRead
            pollControls();
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

                linIdx = measurementEngine.computeFlatLinIdx_(layout, li, count);
                channelIdx = (meta.offset0(li) + (1:meta.nScalarGet(li))).';
                for k = 1:meta.nScalarGet(li)
                    data{channelIdx(k)}(linIdx) = newdata(k);
                end
                appendDirty(channelIdx, linIdx, newdata(1:numel(channelIdx)), li == saveLI);

                for k = 1:numDisp
                    rL = pRL(k);
                    if rL > 0 && count(rL) ~= pLR(k)
                        appendReset(k);
                        pLR(k) = count(rL);
                    end
                end

                dIdxs = pByLoop{li};
                for j = 1:numel(dIdxs)
                    k = dIdxs(j);
                    lI = pLI(k);
                    if lI >= 1 && lI <= numel(newdata)
                        if pYL(k) > 0
                            appendPlot(k, count(pXL(k)), count(pYL(k)), newdata(lI));
                        else
                            appendPlot(k, count(pXL(k)), 1, newdata(lI));
                        end
                    end
                end

                if toc(lastSnapTic) >= snapInt_s
                    flushDirty(false);
                end
            end
        end

        pollControls();
        if stopped, break; end

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

    flushDirty(true);

    function pollControls()
        while clientToEngine.QueueLength > 0
            ctl = poll(clientToEngine);
            if ~isstruct(ctl) || ~isfield(ctl, "type")
                continue;
            end
            if isfield(ctl, "requestId") && ctl.requestId ~= requestId
                continue;
            end
            if ctl.type == "stop"
                stopped = true;
            elseif ctl.type == "turboReady"
                if ~isfield(ctl, "seq") || double(ctl.seq) == inFlightSeq
                    updateInFlight = false;
                end
            end
        end
    end

    function flushDirty(force)
        pollControls();
        if dirtyN == 0 && plotN == 0 && resetN == 0
            return;
        end
        if force
            while updateInFlight
                pollControls();
                if updateInFlight
                    pause(1E-6);
                end
            end
        elseif updateInFlight
            return;
        end

        nextSeq = nextSeq + 1;
        send(engineToClient, struct( ...
            "type", "turboDirty", ...
            "requestId", requestId, ...
            "seq", nextSeq, ...
            "count", count, ...
            "channelIdx", dirtyChannelIdx(1:dirtyN), ...
            "flatIdx", dirtyFlatIdx(1:dirtyN), ...
            "values", dirtyValues(1:dirtyN), ...
            "plotDispIdx", plotDispIdx(1:plotN), ...
            "plotX", plotX(1:plotN), ...
            "plotY", plotY(1:plotN), ...
            "plotValues", plotValues(1:plotN), ...
            "resetDispIdx", resetDispIdx(1:resetN), ...
            "saveLoopHit", dirtySaveLoopHit));
        updateInFlight = true;
        inFlightSeq = nextSeq;
        dirtyN = 0;
        plotN = 0;
        resetN = 0;
        dirtySaveLoopHit = false;
        lastSnapTic = tic;
        if enableLog && ~firstDirty
            firstDirty = true;
            msg = "runTurboScanCore_ first turboDirty " + requestId;
            experimentContext.print(msg);
            logFcn(msg);
        end
    end

    function appendDirty(channelIdx, linIdx, values, saveLoopHit)
        n = numel(values);
        ensureDirtyCapacity(n);
        rows = dirtyN + (1:n);
        dirtyChannelIdx(rows) = channelIdx(:);
        dirtyFlatIdx(rows) = linIdx;
        dirtyValues(rows) = values(:);
        dirtyN = dirtyN + n;
        dirtySaveLoopHit = dirtySaveLoopHit || saveLoopHit;
    end

    function appendPlot(displayIdx, xIdx, yIdx, value)
        ensurePlotCapacity(1);
        plotN = plotN + 1;
        plotDispIdx(plotN) = displayIdx;
        plotX(plotN) = xIdx;
        plotY(plotN) = yIdx;
        plotValues(plotN) = value;
    end

    function appendReset(displayIdx)
        if plotN > 0
            oldPlotDispIdx = plotDispIdx(1:plotN);
            oldPlotX = plotX(1:plotN);
            oldPlotY = plotY(1:plotN);
            oldPlotValues = plotValues(1:plotN);
            keepPlot = oldPlotDispIdx ~= displayIdx;
            keptPlotN = nnz(keepPlot);
            plotDispIdx(1:keptPlotN) = oldPlotDispIdx(keepPlot);
            plotX(1:keptPlotN) = oldPlotX(keepPlot);
            plotY(1:keptPlotN) = oldPlotY(keepPlot);
            plotValues(1:keptPlotN) = oldPlotValues(keepPlot);
            plotN = keptPlotN;
        end
        if resetN > 0
            oldResetDispIdx = resetDispIdx(1:resetN);
            keepReset = oldResetDispIdx ~= displayIdx;
            keptResetN = nnz(keepReset);
            resetDispIdx(1:keptResetN) = oldResetDispIdx(keepReset);
            resetN = keptResetN;
        end
        ensureResetCapacity(1);
        resetN = resetN + 1;
        resetDispIdx(resetN) = displayIdx;
    end

    function ensureDirtyCapacity(nExtra)
        needed = dirtyN + nExtra;
        if needed <= dirtyCap
            return;
        end
        dirtyCap = max(needed, dirtyCap * 2);
        dirtyChannelIdx(dirtyCap, 1) = 0;
        dirtyFlatIdx(dirtyCap, 1) = 0;
        dirtyValues(dirtyCap, 1) = 0;
    end

    function ensurePlotCapacity(nExtra)
        needed = plotN + nExtra;
        if needed <= plotCap
            return;
        end
        plotCap = max(needed, plotCap * 2);
        plotDispIdx(plotCap, 1) = 0;
        plotX(plotCap, 1) = 0;
        plotY(plotCap, 1) = 0;
        plotValues(plotCap, 1) = 0;
    end

    function ensureResetCapacity(nExtra)
        needed = resetN + nExtra;
        if needed <= resetCap
            return;
        end
        resetCap = max(needed, resetCap * 2);
        resetDispIdx(resetCap, 1) = 0;
    end

    function interruptiblePause(duration_s)
        rem_ = duration_s;
        while rem_ > 0 && ~stopped
            pollControls();
            if stopped
                break;
            end
            s_ = min(0.05, rem_);
            pause(s_);
            rem_ = rem_ - s_;
        end
    end

    function stoppedOut = rackSetWithStop(channelNames, values, stoppedIn)
        rack.rackSetWrite(channelNames, values);
        stoppedOut = stoppedIn;
        while ~stoppedOut && ~rack.rackSetCheck(channelNames)
            pollControls();
            stoppedOut = stopped;
            pause(1E-6);
        end
    end
end

