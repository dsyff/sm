function payload = smload(folderOrSource, fileNum, nThMatch, varargin)
% SMLOAD Loads smrun_new save data and returns a struct of named variables.
%
% Usage patterns:
%   payload = smload(saveStruct);
%   payload = smload(filename);
%   payload = smload(folder, fileNum);
%   payload = smload(folder, fileNum, nThMatch);
%   payload = smload(___, 'includeRaw', true);
%
% The returned struct contains:
%   .scan        - Original scan struct (scalar)
%   .data        - Raw data cell array from the saved file
%   .channels    - Struct of channel names mapped to data arrays
%   .setchannels - Struct of set channel names mapped to axis vectors
%   .metadata    - File metadata (filename, comments, consts)
%   .raw         - Optional: complete loaded struct when 'includeRaw' is true

if nargin == 0
    error('smload requires at least one input argument.');
end

optionArgs = varargin;
if nargin >= 3 && ~isempty(nThMatch) && ~isnumeric(nThMatch)
    optionArgs = [{nThMatch}, optionArgs];
    nThMatch = [];
end
if nargin >= 2 && ~isempty(fileNum) && ~isnumeric(fileNum)
    optionArgs = [{fileNum}, optionArgs];
    fileNum = [];
end

opts = parseOptions(optionArgs{:});

usingLegacy = (nargin == 1) || (isempty(fileNum) && (nargin < 3 || isempty(nThMatch)));

if usingLegacy
    [scan, data, label, rawStruct] = loadSavePayload(folderOrSource, opts.includeRaw);
else
    if nargin < 2 || isempty(fileNum)
        error('smload requires fileNum when specifying a folder.');
    end
    if nargin < 3 || isempty(nThMatch)
        nThMatch = 1;
    end
    validateattributes(fileNum, {'numeric'}, {'scalar', 'real', 'finite', 'nonnegative'}, mfilename, 'fileNum');
    validateattributes(nThMatch, {'numeric'}, {'scalar', 'real', 'finite', 'positive'}, mfilename, 'nThMatch');

    resolvedFile = locateSaveFile(folderOrSource, fileNum, nThMatch);
    [scan, data, label, rawStruct] = loadSavePayload(resolvedFile, opts.includeRaw);
end

payload = struct();
payload.scan = scan;
payload.data = data;
payload.metadata = buildMetadata(scan, label);

[channelStruct, setStruct] = extractChannels(scan, data);
payload.channels = channelStruct;
payload.setchannels = setStruct;

if opts.includeRaw
    payload.raw = rawStruct;
end

    function optsOut = parseOptions(varargin)
        optsOut.includeRaw = false;
        idx = 1;
        while idx <= numel(varargin)
            key = lower(string(varargin{idx}));
            if idx == numel(varargin)
                error('Missing value for option %s.', key);
            end
            value = varargin{idx + 1};
            switch char(key)
                case 'includeraw'
                    optsOut.includeRaw = logical(value);
                otherwise
                    error('Unknown option %s.', key);
            end
            idx = idx + 2;
        end
    end

    function [scanOut, dataOut, labelOut, rawOut] = loadSavePayload(source, includeRaw)
        if isstruct(source) && isfield(source, 'scan') && isfield(source, 'data')
            payloadStruct = source;
            labelOut = 'struct input';
            rawOut = [];
            if includeRaw
                rawOut = payloadStruct;
            end
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
                if includeRaw
                    payloadStruct = load(source);
                else
                    payloadStruct = load(source, 'scan', 'data');
                end
            catch ME
                error('Failed to load %s (%s).', source, ME.message);
            end
            labelOut = char(source);
            if includeRaw
                rawOut = payloadStruct;
            else
                rawOut = [];
            end
        end

        if ~isfield(payloadStruct, 'scan') || ~isfield(payloadStruct, 'data')
            error('Save data must contain scan and data fields.');
        end

        scanOut = payloadStruct.scan;
        dataOut = payloadStruct.data;
    end

    function metadataOut = buildMetadata(scanStruct, labelText)
        metadataOut = struct();
        metadataOut.filename = char(labelText);
        if isfield(scanStruct, 'comments')
            metadataOut.comments = scanStruct.comments;
        else
            metadataOut.comments = [];
        end
        if isfield(scanStruct, 'consts')
            metadataOut.consts = scanStruct.consts;
        else
            metadataOut.consts = [];
        end
    end

    function [channelMap, setMap] = extractChannels(scanStruct, dataCell)
        channelMap = struct();
        setMap = struct();
        loops = scanStruct.loops;
        dataIndexOffset = 0;

        for loopIdx = 1:numel(loops)
            loopDef = loops(loopIdx);
            getNames = ensureCell(loopDef.getchan);
            setNames = ensureCell(loopDef.setchan);

            for chanIdx = 1:numel(getNames)
                channelName = matlab.lang.makeValidName(getNames{chanIdx});
                dataIndex = dataIndexOffset + chanIdx;
                if dataIndex > numel(dataCell)
                    error('Data cell array is missing channel %s.', channelName);
                end
                channelMap.(channelName) = dataCell{dataIndex};
            end
            dataIndexOffset = dataIndexOffset + numel(getNames);

            if isfield(loopDef, 'setchanranges') && ~isempty(loopDef.setchanranges)
                for setIdx = 1:min(numel(setNames), numel(loopDef.setchanranges))
                    sourceRange = loopDef.setchanranges{setIdx};
                    npoints = loopDef.npoints;
                    setData = linspace(sourceRange(1), sourceRange(end), npoints);
                    rawName = [setNames{setIdx}, '_set'];
                    setName = matlab.lang.makeValidName(rawName);
                    setMap.(setName) = double(setData(:).');
                end
            elseif isfield(loopDef, 'rng') && ~isempty(loopDef.rng)
                axisValues = double(loopDef.rng(:).');
                for setIdx = 1:numel(setNames)
                    rawName = [setNames{setIdx}, '_set'];
                    setName = matlab.lang.makeValidName(rawName);
                    setMap.(setName) = axisValues;
                end
            end
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

    function filenameOut = locateSaveFile(folderInput, fileNumber, matchIndex)
        folderStr = string(folderInput);
        if strlength(folderStr) == 0
            listing = dir('*.mat');
            basePath = string('');
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
end
