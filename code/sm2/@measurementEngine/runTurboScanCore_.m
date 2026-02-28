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
    if ~(isfinite(saveLI) && saveLI >= 1 && mod(saveLI, 1) == 0)
        error("measurementEngine:InvalidSaveLoop", "saveloop must be a positive integer loop index.");
    end
    saveMinInterval_s = seconds(scanObj.saveMinInterval);
    if ~(isfinite(saveMinInterval_s) && saveMinInterval_s > 0)
        error("measurementEngine:InvalidSaveMinInterval", "saveMinInterval must be a finite, positive duration.");
    end
    lastTempSaveTic = [];

    % Set constants.
    stopped = false;
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
            stopped = rackSetWithStop(sc, double([consts(m).val]).', stopped);
            if stopped, return; end
        end
    end

    % Snapshot timing.
    snapInt_s = seconds(snapshotInterval);
    lastSnapTic = tic;

    % --- Main measurement loop ---
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

        batchSetChans = string.empty(0, 1);
        batchSetVals = double.empty(0, 1);
        for li = fliplr(loopsToSet)
            if ~stopped && clientToEngine.QueueLength > 0
                ctl = poll(clientToEngine);
                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                    stopped = true;
                end
            end
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

    function stoppedOut = rackSetWithStop(channelNames, values, stoppedIn)
        rack.rackSetWrite(channelNames, values);
        stoppedOut = stoppedIn;
        while ~stoppedOut && ~rack.rackSetCheck(channelNames)
            if clientToEngine.QueueLength > 0
                ctl = poll(clientToEngine);
                if isstruct(ctl) && isfield(ctl, "type") && ctl.type == "stop"
                    stoppedOut = true;
                end
            end
            pause(1E-6);
        end
    end
end

