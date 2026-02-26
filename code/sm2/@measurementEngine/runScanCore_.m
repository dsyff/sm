function [data, stopped] = runScanCore_(rack, scanObj, onRead, figHandle, snapshotInterval, onSnapshot, onTemp, logFcn, isScanInProgressFcn)
    % Single-threaded scan loop. Stop via figure handle ESC + scan-progress callback.
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
    if nargin < 9
        isScanInProgressFcn = [];
    end

    enableLog = ~isempty(logFcn) && isa(logFcn, "function_handle");
    didLogFirstSet = false;
    didLogFirstGet = false;
    didLogFirstConstSet = false;

    % Stop via figure handle ESC key + scan-progress callback.
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
        if ~(isfinite(saveLoopIdx) && saveLoopIdx >= 1 && mod(saveLoopIdx, 1) == 0)
            error("measurementEngine:InvalidSaveLoop", "saveloop must be a positive integer loop index.");
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
        if ~stopped, stopped = shouldStop(); end
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

        batchSetChans = string.empty(0, 1);
        batchSetVals = double.empty(0, 1);
        for loopIdx = fliplr(loopsToSet)
            if ~stopped, stopped = shouldStop(); end
            if stopped
                if ~isempty(batchSetChans)
                    if enableLog && ~didLogFirstSet
                        didLogFirstSet = true;
                        pairs = compose("%s=%g", batchSetChans(:), batchSetVals(:));
                        logFcn("runScanCore_ first rackSet n=" + numel(batchSetChans) + " " + strjoin(pairs, ", "));
                    end
                    rack.rackSet(batchSetChans, batchSetVals);
                    batchSetChans = string.empty(0, 1);
                    batchSetVals = double.empty(0, 1);
                end
                break;
            end

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

            startwaitSecs = seconds(startwaitByLoop(loopIdx));
            waittimeSecs = seconds(waittimeByLoop(loopIdx));
            if (count(loopIdx) == 1 && startwaitSecs > 0) || waittimeSecs > 0
                if enableLog && ~didLogFirstSet
                    didLogFirstSet = true;
                    pairs = compose("%s=%g", batchSetChans(:), batchSetVals(:));
                    logFcn("runScanCore_ first rackSet n=" + numel(batchSetChans) + " " + strjoin(pairs, ", "));
                end
                rack.rackSet(batchSetChans, batchSetVals);
                batchSetChans = string.empty(0, 1);
                batchSetVals = double.empty(0, 1);
                if count(loopIdx) == 1 && measurementEngine.waitWithStop_(startwaitByLoop(loopIdx), figHandle, isScanInProgressFcn)
                    stopped = true;
                    break;
                end
                if measurementEngine.waitWithStop_(waittimeByLoop(loopIdx), figHandle, isScanInProgressFcn)
                    stopped = true;
                    break;
                end
                if ~stopped, stopped = shouldStop(); end
            end
        end
        if ~isempty(batchSetChans)
            if enableLog && ~didLogFirstSet
                didLogFirstSet = true;
                pairs = compose("%s=%g", batchSetChans(:), batchSetVals(:));
                logFcn("runScanCore_ first rackSet n=" + numel(batchSetChans) + " " + strjoin(pairs, ", "));
            end
            rack.rackSet(batchSetChans, batchSetVals);
        end

        if ~stopped, stopped = shouldStop(); end
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
            if ~stopped, stopped = shouldStop(); end
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

        if ~stopped, stopped = shouldStop(); end
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

    function tf = shouldStop()
        tf = false;
        try
            if isequal(get(figHandle, "CurrentCharacter"), char(27))
                set(figHandle, "CurrentCharacter", char(0));
                tf = true;
            end
        catch
        end
        if tf || isempty(isScanInProgressFcn)
            return;
        end
        try
            tf = ~logical(isScanInProgressFcn());
        catch
        end
    end
end

