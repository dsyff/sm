function scanOut = smscanSanitizeForBridge(scanIn)
%SMSCANSANITIZEFORBRIDGE Filter a scan against the currently available channels.
% - Drops getchan entries that no longer exist (vector names).
% - Drops setchan entries that no longer exist (pure scalar names).
% - Drops disp entries whose selected plotted scalar channel name no longer exists.
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

for loopIdx = 1:numel(scanOut.loops)
    loopDef = scanOut.loops(loopIdx);

    if isfield(loopDef, "getchan")
        getNames = string(loopDef.getchan);
        getNames = getNames(:).';
        keepGet = ismember(getNames, vectorNames);
        scanOut.loops(loopIdx).getchan = cellstr(getNames(keepGet).');
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

validMask = true(1, numel(scanOut.disp));
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
    if strlength(dispName) == 0 || ~any(plotNames == dispName)
        validMask(dispIdx) = false;
        continue;
    end
    scanOut.disp(dispIdx).name = dispName;
    scanOut.disp(dispIdx).channel = find(plotNames == dispName, 1);
end

scanOut.disp = scanOut.disp(validMask);
end

