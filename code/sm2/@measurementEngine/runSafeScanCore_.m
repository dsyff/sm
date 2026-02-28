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
            stopped = rackSetWithStop(sc, double([consts(m).val]).', stopped);
            if stopped, return; end
        end
    end

    % --- Main loop ---
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
                        msg = "runSafeScanCore_ first rackSet n=" + numel(batchSetChans);
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
                    msg = "runSafeScanCore_ first rackSet n=" + numel(batchSetChans);
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
                msg = "runSafeScanCore_ first rackSet n=" + numel(batchSetChans);
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
                        pause(1E-6);
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
