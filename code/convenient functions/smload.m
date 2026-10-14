function payload = smload(folderOrSource, varargin)
% SMLOAD Loads saved scan data and returns a struct of named variables.
%
% Usage patterns:
%   payload = smload(saveStruct);
%   payload = smload(filename);
%   payload = smload(folder, fileNum);
%   payload = smload(folder, fileNum, nThMatch);
%   payload = smload(___, 'includeRaw', true);
% Numbered lookup skips definition-only files by checking their MAT variables.
% Set axes follow acquisition ranges, including index axes when no range is set.
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

fileNum = [];
nThMatch = [];
if ~isempty(varargin) && isnumeric(varargin{1})
    fileNum = varargin{1};
    varargin(1) = [];
    if ~isempty(varargin) && isnumeric(varargin{1})
        nThMatch = varargin{1};
        varargin(1) = [];
    end
end
opts = parseOptions(varargin{:});

[saved, label] = smReadSavePayload(folderOrSource, fileNum, nThMatch, opts.includeRaw);
scan = saved.scan;
data = saved.data;

payload = struct();
payload.scan = scan;
payload.data = data;
payload.metadata = buildMetadata(scan, label);

[channelStruct, setStruct] = extractChannels(scan, data);
payload.channels = channelStruct;
payload.setchannels = setStruct;

if opts.includeRaw
    payload.raw = saved;
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
                    validateattributes(value, {'logical', 'numeric'}, {'scalar', 'binary'}, mfilename, 'includeRaw');
                    optsOut.includeRaw = logical(value);
                otherwise
                    error('Unknown option %s.', key);
            end
            idx = idx + 2;
        end
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
                    error('smload:ChannelCountMismatch', 'Data cell array is missing channel %s.', channelName);
                end
                if isfield(channelMap, channelName)
                    error('smload:DuplicateChannelName', 'Multiple channels map to field %s.', channelName);
                end
                channelMap.(channelName) = dataCell{dataIndex};
            end
            dataIndexOffset = dataIndexOffset + numel(getNames);

            for setIdx = 1:numel(setNames)
                sourceRange = [];
                if isfield(loopDef, 'setchanranges') && ~isempty(loopDef.setchanranges)
                    if setIdx <= numel(loopDef.setchanranges)
                        sourceRange = loopDef.setchanranges{setIdx};
                    end
                elseif isfield(loopDef, 'rng') && numel(loopDef.rng) >= 2
                    sourceRange = loopDef.rng;
                end
                npoints = loopDef.npoints;
                if isempty(sourceRange)
                    setData = 1:npoints;
                elseif npoints > 1 && numel(sourceRange) >= 2
                    setData = linspace(sourceRange(1), sourceRange(2), npoints);
                else
                    setData = repmat(sourceRange(1), 1, npoints);
                end
                setName = matlab.lang.makeValidName([setNames{setIdx}, '_set']);
                if isfield(setMap, setName)
                    error('smload:DuplicateChannelName', 'Multiple set channels map to field %s.', setName);
                end
                setMap.(setName) = double(setData(:).');
            end
        end
        if dataIndexOffset ~= numel(dataCell)
            error('smload:ChannelCountMismatch', 'Channel count in data does not match scan definition.');
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

end
