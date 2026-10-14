function smplot(folderOrSource, varargin)
% SMPLOT Replicates the final scan figure from saved scan data.
%   smplot(filename), smplot(saveStruct), or smplot(folder, fileNum, nThMatch).
%   Optional name/value pairs: "figure", figureNumber; "disp", displayStruct.
%   Incomplete saves show the latest outer slice containing non-NaN data.

if nargin == 0
    error('smplot requires at least a folder or save payload.');
end

sourceArgs = {folderOrSource};
for k = 1:min(2, numel(varargin))
    if ~isnumeric(varargin{1})
        break;
    end
    sourceArgs{end + 1} = varargin{1};
    varargin(1) = [];
end
opts = parseOptions(varargin{:});
[payload, sourceLabel] = smReadSavePayload(sourceArgs{:});
scan = payload.scan;
data = payload.data;

if ~isstruct(scan) || ~isfield(scan, 'loops')
    error('Scan structure is missing loop definitions.');
end

scandef = scan.loops;
nloops = numel(scandef);
if nloops == 0
    error('Scan definition contains no loops.');
end

npoints = zeros(1, nloops);
for loopIdx = 1:nloops
    if isfield(scandef(loopIdx), 'npoints') && ~isempty(scandef(loopIdx).npoints)
        npoints(loopIdx) = double(scandef(loopIdx).npoints);
    else
        error('Loop %d is missing npoints.', loopIdx);
    end
end

[channelNames, dataloop] = extractChannelMetadata(scandef);
numChannels = numel(channelNames);
if numel(data) ~= numChannels
    error('Channel count in data does not match scan definition.');
end

dispStruct = resolveDisplay(opts.dispOverride, scan, dataloop);

[axisValues, axisLabels] = buildAxes(scandef, npoints);

figNum = chooseFigureNumber(opts.figureOverride, scan);
figHandle = figure(figNum);
clf(figHandle);
try
    figHandle.WindowState = 'maximized';
catch
end

[sourcePath, sourceName, sourceExt] = fileparts(sourceLabel);
if isempty(sourceName)
    titleRoot = char(sourceLabel);
else
    titleRoot = char(fullfile(sourcePath, [sourceName sourceExt]));
end

subplotShape = determineLayout(numel(dispStruct));
sgtitle(figHandle, sprintf('Data from: %s', titleRoot), 'Interpreter', 'none');

axisLabelFontSize = 14;
axisTickFontSize = 12;

for dispIdx = 1:numel(dispStruct)
    subplot(subplotShape(1), subplotShape(2), dispIdx, 'Parent', figHandle);
    entry = dispStruct(dispIdx);
    currentAxes = gca;
    set(currentAxes, 'FontSize', axisTickFontSize);
    chanIdx = entry.channel;
    if chanIdx < 1 || chanIdx > numChannels
        title(sprintf('Display %d (invalid channel)', dispIdx));
        continue;
    end

    raw = data{chanIdx};
    if isempty(raw)
        title(sprintf('Channel %d (no data)', chanIdx));
        continue;
    end

    channelLoop = dataloop(chanIdx);
    xAxis = axisValues{channelLoop};
    if entry.dim == 2 && channelLoop < nloops
        zData = extractSlice(raw, channelLoop, 2);
        yAxis = axisValues{channelLoop + 1};
        imagesc(xAxis, yAxis, zData, AlphaData=~isnan(zData));
        set(gca, 'YDir', 'normal');
        cb = colorbar;
        set(cb, 'FontSize', axisTickFontSize);
        set(gca, 'XLim', computeAxisLimits(xAxis), 'YLim', computeAxisLimits(yAxis));
        applyAxisLabel(gca, 'y', formatLabel(channelLoop + 1, axisLabels));
    else
        lineData = extractSlice(raw, channelLoop, 1);
        plot(xAxis, lineData);
        set(gca, 'XLim', computeAxisLimits(xAxis));
        applyAxisLabel(gca, 'y', channelTitle(chanIdx, channelNames));
    end
    applyAxisLabel(gca, 'x', formatLabel(channelLoop, axisLabels));

    set(gca, 'FontSize', axisTickFontSize);
    applyCompactTickFormat(gca);
    title(channelTitle(chanIdx, channelNames));
end

if isfield(scan, 'comments') && ~isempty(scan.comments)
    if iscell(scan.comments)
        commentText = strjoin(scan.comments, '; ');
    else
        commentText = char(scan.comments);
    end
    fprintf('Scan comments: %s\n', commentText);
end

fprintf('Plot created from: %s\n', char(sourceLabel));

    function optsOut = parseOptions(varargin)
        optsOut.figureOverride = [];
        optsOut.dispOverride = [];
        idx = 1;
        while idx <= numel(varargin)
            key = lower(string(varargin{idx}));
            if idx == numel(varargin)
                error('Missing value for parameter %s.', key);
            end
            value = varargin{idx + 1};
            switch char(key)
                case 'figure'
                    if ~(isnumeric(value) && isscalar(value))
                        error('Figure parameter must be a numeric scalar.');
                    end
                    optsOut.figureOverride = double(value);
                case 'disp'
                    if ~isstruct(value)
                        error('Disp override must be a struct array.');
                    end
                    optsOut.dispOverride = value;
                otherwise
                    error('Unknown parameter %s.', key);
            end
            idx = idx + 2;
        end
    end

    function [names, loops] = extractChannelMetadata(definition)
        names = {};
        loops = [];
        for defIdx = 1:numel(definition)
            loopChans = ensureCell(definition(defIdx).getchan);
            names = [names, loopChans];
            loops = [loops, repmat(defIdx, 1, numel(loopChans))];
        end
    end

    function cellArray = ensureCell(value)
        if isempty(value)
            cellArray = {};
        elseif iscell(value)
            cellArray = value(:).';
        elseif isstring(value)
            cellArray = cellstr(value(:).');
        else
            cellArray = {value};
        end
        for idx = 1:numel(cellArray)
            if isstring(cellArray{idx})
                cellArray{idx} = char(cellArray{idx});
            end
        end
    end

    function dispOut = resolveDisplay(overrideDisp, scanStruct, loopMap)
        if ~isempty(overrideDisp)
            dispOut = overrideDisp;
        elseif isfield(scanStruct, 'disp') && ~isempty(scanStruct.disp)
            dispOut = scanStruct.disp;
        else
            dispOut = struct('channel', {}, 'dim', {}, 'loop', {});
            for idx = 1:numel(loopMap)
                dispOut(idx).channel = idx;
                dispOut(idx).dim = 1;
                dispOut(idx).loop = max(1, loopMap(idx));
            end
        end
        if ~isstruct(dispOut)
            error('Display override must be a struct array.');
        end
        dispOut = dispOut(:).';
        for idx = 1:numel(dispOut)
            if ~isfield(dispOut(idx), 'channel') || isempty(dispOut(idx).channel)
                dispOut(idx).channel = idx;
            end
            if ~isfield(dispOut(idx), 'dim') || isempty(dispOut(idx).dim)
                dispOut(idx).dim = 1;
            end
            if ~isfield(dispOut(idx), 'loop') || isempty(dispOut(idx).loop)
                chanIdx = dispOut(idx).channel;
                if chanIdx >= 1 && chanIdx <= numel(loopMap)
                    dispOut(idx).loop = max(1, loopMap(chanIdx));
                else
                    dispOut(idx).loop = 1;
                end
            end
            dispOut(idx).dim = max(1, round(dispOut(idx).dim));
        end
    end

    function [valuesOut, labelsOut] = buildAxes(definition, pointCounts)
        valuesOut = cell(1, numel(definition));
        labelsOut = cell(1, numel(definition));
        for defIdx = 1:numel(definition)
            loopDef = definition(defIdx);
            valuesOut{defIdx} = calculateAxis(loopDef, pointCounts(defIdx));
            labelsOut{defIdx} = axisLabel(loopDef, defIdx);
        end
    end

    function vals = calculateAxis(loopDef, count)
        sourceRange = [];
        if isfield(loopDef, 'setchanranges') && ~isempty(loopDef.setchanranges)
            sourceRange = loopDef.setchanranges{1};
        elseif isfield(loopDef, 'rng') && numel(loopDef.rng) >= 2
            sourceRange = loopDef.rng;
        end
        if isempty(sourceRange)
            vals = 1:count;
        elseif count > 1 && numel(sourceRange) >= 2
            vals = linspace(sourceRange(1), sourceRange(2), count);
        else
            vals = repmat(sourceRange(1), 1, count);
        end
        vals = double(vals(:).');
    end

    function lbl = axisLabel(loopDef, loopNumber)
        lbl = '';
        if isfield(loopDef, 'setchan') && ~isempty(loopDef.setchan)
            chanNames = ensureCell(loopDef.setchan);
            if ~isempty(chanNames)
                lbl = char(chanNames{1});
            end
        end
        if isempty(lbl)
            lbl = sprintf('Loop %d', loopNumber);
        end
    end

    function figValue = chooseFigureNumber(overrideValue, scanStruct)
        if ~isempty(overrideValue)
            figValue = overrideValue;
            return;
        end
        if isfield(scanStruct, 'figure') && ~isempty(scanStruct.figure)
            figValue = double(scanStruct.figure);
            if isnan(figValue)
                figValue = 2000;
            end
        else
            figValue = 2000;
        end
    end

    function layout = determineLayout(count)
        switch count
            case 0
                layout = [1 1];
            case 1
                layout = [1 1];
            case 2
                layout = [1 2];
            case {3,4}
                layout = [2 2];
            case {5,6}
                layout = [2 3];
            case {7,8,9}
                layout = [3 3];
            case {10,11,12}
                layout = [3 4];
            case {13,14,15,16}
                layout = [4 4];
            case {17,18,19,20}
                layout = [4 5];
            case {21,22,23,24,25}
                layout = [5 5];
            case {26,27,28,29,30}
                layout = [5 6];
            otherwise
                layout = [6 6];
        end
    end

    function values = extractSlice(rawData, channelLoop, displayDims)
        loopCount = nloops - channelLoop + 1;
        if numel(rawData) ~= prod(npoints(channelLoop:end))
            error("smplot:DataShapeMismatch", "Data size does not match loop point counts.");
        end
        % Put the fastest loop first, including implicit trailing singletons.
        scanOrder = permute(rawData, [loopCount:-1:1, loopCount+1:max(2, loopCount)]);
        sliceSize = prod(npoints(channelLoop:channelLoop + displayDims - 1));
        slices = reshape(scanOrder, sliceSize, []);
        sliceIndex = size(slices, 2);
        if ~isfield(scan, "isComplete") || ~scan.isComplete
            lastStored = find(any(~isnan(slices), 1), 1, "last");
            if ~isempty(lastStored)
                sliceIndex = lastStored;
            end
        end
        values = double(reshape(slices(:, sliceIndex), npoints(channelLoop), []).');
    end

    function lbl = formatLabel(loopIdx, labelsCell)
        if loopIdx >= 1 && loopIdx <= numel(labelsCell) && ~isempty(labelsCell{loopIdx})
            lbl = strrep(labelsCell{loopIdx}, '_', '\_');
        else
            if loopIdx > 0
                lbl = sprintf('Loop %d', loopIdx);
            else
                lbl = '';
            end
        end
    end

    function lbl = channelTitle(idx, namesCell)
        if idx >= 1 && idx <= numel(namesCell) && ~isempty(namesCell{idx})
            lbl = strrep(char(namesCell{idx}), '_', '\_');
        else
            lbl = sprintf('Channel %d', idx);
        end
    end

    function limits = computeAxisLimits(axisValues)
        axisValues = double(axisValues(:));
        if isempty(axisValues)
            limits = [0 1];
        else
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
    end

    function applyAxisLabel(axHandle, axisIdentifier, labelText)
        if nargin < 3 || isempty(labelText)
            labelText = '';
        end
        switch axisIdentifier
            case 'x'
                labelHandle = xlabel(axHandle, labelText);
            case 'y'
                labelHandle = ylabel(axHandle, labelText);
            otherwise
                return;
        end
        if isgraphics(labelHandle)
            set(labelHandle, 'FontSize', axisLabelFontSize);
        end
    end
end
