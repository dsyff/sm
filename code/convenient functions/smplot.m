function smplot(folderOrSource, fileNum, nThMatch, varargin)
% SMPLOT Replicates the final scan figure from saved scan data.

if nargin == 0
    error('smplot requires at least a folder or save payload.');
end

legacyInvocation = (nargin == 1) && (ischar(folderOrSource) || isstring(folderOrSource) || isstruct(folderOrSource));
if legacyInvocation
    opts = parseOptions(varargin{:});
    [scan, data, sourceLabel] = loadSaveData(folderOrSource);
else
    if nargin < 2
        error('smplot requires folder and fileNum when using the new interface.');
    end

    additionalArgs = varargin;
    if nargin < 3 || isempty(nThMatch)
        nThMatch = 1;
    elseif ischar(nThMatch) || isstring(nThMatch) || isstruct(nThMatch)
        additionalArgs = [{nThMatch}, additionalArgs];
        nThMatch = 1;
    end

    validateattributes(fileNum, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, 'fileNum');
    validateattributes(nThMatch, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'nThMatch');

    opts = parseOptions(additionalArgs{:});
    resolvedFile = locateSaveFile(folderOrSource, fileNum, nThMatch);
    [scan, data, sourceLabel] = loadSaveData(resolvedFile);
end

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
    dimSetting = entry.dim;

    if dimSetting == 2
        [isSurface, zData, loopX, loopY] = extractSurface(raw, channelLoop);
        if isSurface
            xAxis = buildAxis(loopX, size(zData, 2), axisValues);
            yAxis = buildAxis(loopY, size(zData, 1), axisValues);
            imagesc(xAxis, yAxis, zData);
            set(gca, 'YDir', 'normal');
            cb = colorbar;
            set(cb, 'FontSize', axisTickFontSize);
            set(gca, 'XLim', computeAxisLimits(xAxis), 'YLim', computeAxisLimits(yAxis));
            applyAxisLabel(gca, 'x', formatLabel(loopX, axisLabels));
            applyAxisLabel(gca, 'y', formatLabel(loopY, axisLabels));
        else
            [lineData, loopUsed] = extractLine(raw, channelLoop, entry.loop);
            xAxis = buildAxis(loopUsed, numel(lineData), axisValues);
            plot(xAxis, lineData);
            set(gca, 'XLim', computeAxisLimits(xAxis));
            applyAxisLabel(gca, 'x', formatLabel(loopUsed, axisLabels));
            applyAxisLabel(gca, 'y', channelTitle(chanIdx, channelNames));
        end
    else
        [lineData, loopUsed] = extractLine(raw, channelLoop, entry.loop);
        xAxis = buildAxis(loopUsed, numel(lineData), axisValues);
        plot(xAxis, lineData);
        set(gca, 'XLim', computeAxisLimits(xAxis));
        applyAxisLabel(gca, 'x', formatLabel(loopUsed, axisLabels));
        applyAxisLabel(gca, 'y', channelTitle(chanIdx, channelNames));
    end

    set(gca, 'FontSize', axisTickFontSize);
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

    function [scanOut, dataOut, labelOut] = loadSaveData(source)
        if isstruct(source)
            payload = source;
            labelOut = 'struct input';
        else
            if isstring(source)
                source = char(source);
            end
            if ~(ischar(source) || isstring(source))
                error('Filename must be a character vector or string.');
            end
            if ~exist(source, 'file')
                error('File %s does not exist.', source);
            end
            try
                payload = load(source);
            catch ME
                error('Failed to load %s (%s).', source, ME.message);
            end
            labelOut = char(source);
        end
        if ~isfield(payload, 'scan') || ~isfield(payload, 'data')
            error('Save data must contain scan and data fields.');
        end
        scanOut = payload.scan;
        dataOut = payload.data;
    end

    function filenameOut = locateSaveFile(folderInput, fileNumber, matchIndex)
        folderStr = string(folderInput);
        if strlength(folderStr) == 0
            listing = dir('*.mat');
            basePath = "";
        else
            listing = dir(fullfile(folderStr, '*.mat'));
            basePath = folderStr;
        end

        if isempty(listing)
            error('No .mat files found in %s.', chooseDisplayPath(basePath));
        end

        names = {listing.name};
        prefix = sprintf('%03u', round(fileNumber));
        matches = find(startsWith(names, prefix));

        if isempty(matches)
            error('No matching data file found for %s in %s.', prefix, chooseDisplayPath(basePath));
        end
        if numel(matches) < matchIndex
            error('Requested match %d exceeds available files (%d).', matchIndex, numel(matches));
        end

        targetEntry = listing(matches(matchIndex));
        if strlength(basePath) == 0
            filenameOut = targetEntry.name;
        else
            filenameOut = fullfile(basePath, targetEntry.name);
        end
        disp("loading " + filenameOut);
    end

    function displayPath = chooseDisplayPath(pathInput)
        if strlength(pathInput) == 0
            displayPath = '.';
        else
            displayPath = char(pathInput);
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
            cellArray = value;
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
        vals = [];
        if isfield(loopDef, 'setchanranges') && ~isempty(loopDef.setchanranges)
            firstRange = loopDef.setchanranges{1};
            if numel(firstRange) >= 2
                vals = linspace(firstRange(1), firstRange(2), count);
            elseif isscalar(firstRange)
                vals = repmat(firstRange(1), 1, count);
            end
        elseif isfield(loopDef, 'rng') && ~isempty(loopDef.rng)
            vals = double(loopDef.rng(:).');
        end
        if isempty(vals)
            vals = 1:count;
        else
            vals = double(vals(:).');
            if numel(vals) ~= count
                vals = linspace(vals(1), vals(end), count);
            end
        end
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

    function [loopForDim, dimForLoop] = dimensionMaps(channelLoop, rawData)
        sizeVector = size(rawData);
        dimCount = numel(sizeVector);
        loopForDim = zeros(1, dimCount);
        loopsDesc = nloops:-1:channelLoop;
        limit = min(numel(loopsDesc), dimCount);
        loopForDim(1:limit) = loopsDesc(1:limit);
        dimForLoop = zeros(1, nloops);
        for dimIdx = 1:dimCount
            loopNumber = loopForDim(dimIdx);
            if loopNumber ~= 0
                dimForLoop(loopNumber) = dimIdx;
            end
        end
    end

    function [lineValues, loopUsed] = extractLine(rawData, channelLoop, preferredLoop)
        [~, dimForLoop] = dimensionMaps(channelLoop, rawData);
        availableLoops = find(dimForLoop > 0);
        if isempty(availableLoops)
            lineValues = double(rawData(:).');
            loopUsed = 0;
            return;
        end
        loopCandidate = preferredLoop;
        if ~(loopCandidate >= 1 && loopCandidate <= nloops && dimForLoop(loopCandidate) > 0)
            loopCandidate = availableLoops(1);
        end
        dimIdx = dimForLoop(loopCandidate);
        permOrder = [dimIdx, setdiff(1:ndims(rawData), dimIdx, 'stable')];
        permuted = permute(rawData, permOrder);
        idx = repmat({':'}, 1, ndims(permuted));
        for d = 2:ndims(permuted)
            idx{d} = size(permuted, d);
        end
        slice = squeeze(permuted(idx{:}));
        lineValues = double(slice(:).');
        loopUsed = loopCandidate;
    end

    function [isSurface, surfaceData, loopX, loopY] = extractSurface(rawData, channelLoop)
        [~, dimForLoop] = dimensionMaps(channelLoop, rawData);
        availableLoops = find(dimForLoop > 0);
        if numel(availableLoops) < 2
            isSurface = false;
            surfaceData = [];
            loopX = 0;
            loopY = 0;
            return;
        end
        loopX = availableLoops(1);
        loopY = availableLoops(2);
        dimX = dimForLoop(loopX);
        dimY = dimForLoop(loopY);
        permOrder = [dimY, dimX, setdiff(1:ndims(rawData), [dimY, dimX], 'stable')];
        permuted = permute(rawData, permOrder);
        idx = repmat({':'}, 1, ndims(permuted));
        for d = 3:ndims(permuted)
            idx{d} = size(permuted, d);
        end
        slice = squeeze(permuted(idx{:}));
        surfaceData = double(slice);
        isSurface = true;
    end

    function axisVals = buildAxis(loopIdx, expectedLength, allAxes)
        if loopIdx >= 1 && loopIdx <= numel(allAxes) && ~isempty(allAxes{loopIdx})
            axisVals = allAxes{loopIdx};
        else
            axisVals = [];
        end
        if isempty(axisVals)
            axisVals = 1:expectedLength;
        else
            axisVals = double(axisVals(:).');
            if numel(axisVals) ~= expectedLength && expectedLength > 1
                axisVals = linspace(axisVals(1), axisVals(end), expectedLength);
            elseif numel(axisVals) ~= expectedLength
                axisVals = repmat(axisVals(1), 1, expectedLength);
            end
        end
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
