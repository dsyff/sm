function scanOut = smscanSanitizeForBridge(scanIn)
%SMSCANSANITIZEFORBRIDGE Filter a scan against the currently available channels.
% - Accepts GUI-style vector getchan names and saved scalar-expanded getchan lists.
% - Drops getchan entries that no longer exist.
% - Drops setchan entries that no longer exist (pure scalar names).
% - Rebuilds disp entries whose selected plotted scalar channel names still exist.
% - Silent: returns [] when input is invalid.

global bridge

scanOut = scanIn;
if ~isstruct(scanOut) || ~isfield(scanOut, "loops")
    scanOut = [];
    return;
end

if ~(exist("bridge", "var") && ~isempty(bridge) && isobject(bridge))
    if isfield(scanOut, "disp")
        scanOut.disp = [];
    end
    return;
end

vectorNames = string(bridge.getVectorChannelNames());
pureScalarNames = string(bridge.getPureScalarChannelNames());
vectorSizes = zeros(1, numel(vectorNames));
for vectorIdx = 1:numel(vectorNames)
    vectorSizes(vectorIdx) = bridge.getChannelSize(vectorNames(vectorIdx));
end

for loopIdx = 1:numel(scanOut.loops)
    loopDef = scanOut.loops(loopIdx);

    if isfield(loopDef, "getchan")
        getNames = string(loopDef.getchan);
        getNames = getNames(:).';
        normalizedGet = strings(0, 1);
        nameIdx = 1;
        while nameIdx <= numel(getNames)
            chanName = getNames(nameIdx);
            if any(vectorNames == chanName)
                normalizedGet(end+1, 1) = chanName; %#ok<AGROW>
                nameIdx = nameIdx + 1;
                continue;
            end

            matchedSavedVector = false;
            for vectorIdx = 1:numel(vectorNames)
                chanSize = vectorSizes(vectorIdx);
                if chanSize <= 1 || chanName ~= vectorNames(vectorIdx) + "_1"
                    continue;
                end
                expectedNames = strings(1, chanSize);
                for vecIdx = 1:chanSize
                    expectedNames(vecIdx) = vectorNames(vectorIdx) + "_" + vecIdx;
                end
                lastIdx = nameIdx + chanSize - 1;
                if lastIdx <= numel(getNames) && isequal(getNames(nameIdx:lastIdx), expectedNames)
                    normalizedGet(end+1, 1) = vectorNames(vectorIdx); %#ok<AGROW>
                    nameIdx = lastIdx + 1;
                else
                    nameIdx = nameIdx + 1;
                end
                matchedSavedVector = true;
                break;
            end
            if ~matchedSavedVector
                nameIdx = nameIdx + 1;
            end
        end
        keepGet = ismember(normalizedGet, vectorNames);
        scanOut.loops(loopIdx).getchan = cellstr(normalizedGet(keepGet).');
    end

    if isfield(loopDef, "setchan")
        setNames = string(loopDef.setchan);
        setNames = setNames(:).';
        keepSet = ismember(setNames, pureScalarNames);
        scanOut.loops(loopIdx).setchan = cellstr(setNames(keepSet).');

        if isfield(loopDef, "setchanranges") && iscell(loopDef.setchanranges)
            if numel(loopDef.setchanranges) == numel(setNames)
                scanOut.loops(loopIdx).setchanranges = loopDef.setchanranges(keepSet);
            else
                scanOut.loops(loopIdx).setchanranges = {};
            end
        end

        scanOut.loops(loopIdx).numchans = numel(scanOut.loops(loopIdx).setchan);
    end
end

if ~isfield(scanOut, "disp") || isempty(scanOut.disp)
    scanOut.disp = [];
    return;
end

totalPlotNames = 0;
for loopIdx = 1:numel(scanOut.loops)
    loopDef = scanOut.loops(loopIdx);
    if ~isfield(loopDef, "getchan") || isempty(loopDef.getchan)
        continue;
    end
    loopGetNames = string(loopDef.getchan);
    loopGetNames = loopGetNames(:).';
    for nameIdx = 1:numel(loopGetNames)
        chanName = loopGetNames(nameIdx);
        chanSize = bridge.getChannelSize(chanName);
        totalPlotNames = totalPlotNames + max(1, chanSize);
    end
end

plotNames = strings(1, totalPlotNames);
plotNameIdx = 1;
for loopIdx = 1:numel(scanOut.loops)
    loopDef = scanOut.loops(loopIdx);
    if ~isfield(loopDef, "getchan") || isempty(loopDef.getchan)
        continue;
    end
    loopGetNames = string(loopDef.getchan);
    loopGetNames = loopGetNames(:).';
    for nameIdx = 1:numel(loopGetNames)
        chanName = loopGetNames(nameIdx);
        chanSize = bridge.getChannelSize(chanName);
        if chanSize > 1
            for vecIdx = 1:chanSize
                plotNames(plotNameIdx) = chanName + "_" + vecIdx;
                plotNameIdx = plotNameIdx + 1;
            end
        else
            plotNames(plotNameIdx) = chanName;
            plotNameIdx = plotNameIdx + 1;
        end
    end
end

plotLoops = zeros(1, totalPlotNames);
plotNameIdx = 1;
for loopIdx = 1:numel(scanOut.loops)
    loopDef = scanOut.loops(loopIdx);
    if ~isfield(loopDef, "getchan") || isempty(loopDef.getchan)
        continue;
    end
    loopGetNames = string(loopDef.getchan);
    loopGetNames = loopGetNames(:).';
    for nameIdx = 1:numel(loopGetNames)
        chanName = loopGetNames(nameIdx);
        chanSize = bridge.getChannelSize(chanName);
        for vecIdx = 1:max(1, chanSize)
            plotLoops(plotNameIdx) = loopIdx;
            plotNameIdx = plotNameIdx + 1;
        end
    end
end

mask2d = plotLoops < numel(scanOut.loops);
twoDFullIndex = find(mask2d);
fullTo2D = zeros(1, numel(plotNames));
if ~isempty(twoDFullIndex)
    fullTo2D(twoDFullIndex) = 1:numel(twoDFullIndex);
end

oneDvals = [];
twoDvals = [];
for dispIdx = 1:numel(scanOut.disp)
    dispName = "";
    if isfield(scanOut.disp, "name")
        dispName = string(scanOut.disp(dispIdx).name);
    end
    if strlength(dispName) == 0 && isfield(scanOut.disp, "channel")
        channel_idx = scanOut.disp(dispIdx).channel;
        if isnumeric(channel_idx) && isscalar(channel_idx) && channel_idx >= 1 && channel_idx <= numel(plotNames)
            dispName = plotNames(channel_idx);
        end
    end
    if strlength(dispName) == 0
        continue;
    end
    channel_idx = find(plotNames == dispName, 1);
    if isempty(channel_idx)
        continue;
    end
    if isfield(scanOut.disp(dispIdx), "dim") && scanOut.disp(dispIdx).dim == 2
        mappedIdx = fullTo2D(channel_idx);
        if mappedIdx > 0
            twoDvals(end+1) = mappedIdx; %#ok<AGROW>
        end
    else
        oneDvals(end+1) = channel_idx; %#ok<AGROW>
    end
end

oneDvals = unique(sort(oneDvals));
twoDvals = unique(sort(twoDvals));
dispOut = struct("loop", {}, "channel", {}, "dim", {}, "name", {});
entryIdx = 0;
for idx = oneDvals
    entryIdx = entryIdx + 1;
    dispOut(entryIdx).loop = plotLoops(idx);
    dispOut(entryIdx).channel = idx;
    dispOut(entryIdx).dim = 1;
    dispOut(entryIdx).name = plotNames(idx);
end
for localIdx = twoDvals
    fullIdx = twoDFullIndex(localIdx);
    entryIdx = entryIdx + 1;
    dispOut(entryIdx).loop = plotLoops(fullIdx) + 1;
    dispOut(entryIdx).channel = fullIdx;
    dispOut(entryIdx).dim = 2;
    dispOut(entryIdx).name = plotNames(fullIdx);
end

scanOut.disp = dispOut;
end
