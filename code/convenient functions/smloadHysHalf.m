function payload = smloadHysHalf(varargin)
% SMLOADHYSHALF Load with SMLOAD, then keep half of the fast (x) axis.
%
% Usage patterns:
%   payload = smloadHysHalf(folder, fileNum);
%   payload = smloadHysHalf(folder, fileNum, nThMatch);
%   payload = smloadHysHalf(folder, fileNum, nThMatch, true); % second half
%   payload = smloadHysHalf(___, "secondHalf", true);
%   payload = smloadHysHalf(___, "includeRaw", true); % passed to smload
%
% secondHalf defaults to false (first half).

if nargin == 0
    error("smloadHysHalf requires at least one input argument.");
end

[smloadArgs, secondHalf] = parseInputs(varargin{:});
payload = smload(smloadArgs{:});

if ~isfield(payload, "scan") || ~isfield(payload.scan, "loops") || isempty(payload.scan.loops)
    error("smloadHysHalf expected payload.scan.loops from smload.");
end
if ~isfield(payload, "setchannels")
    error("smloadHysHalf expected payload.setchannels from smload.");
end

loop1 = payload.scan.loops(1);
setNames = loopSetNames(loop1);
if isempty(setNames)
    error("smloadHysHalf expected at least one loop-1 set channel.");
end

axisField = "";
for i = 1:numel(setNames)
    candidate = matlab.lang.makeValidName(setNames{i} + "_set");
    if isfield(payload.setchannels, candidate)
        axisField = candidate;
        break;
    end
end
if axisField == ""
    error("smloadHysHalf could not find loop-1 set channel in payload.setchannels.");
end

axisValues = payload.setchannels.(axisField);
if ~isvector(axisValues)
    error("smloadHysHalf expected %s to be a vector.", axisField);
end
nAxis = numel(axisValues);
halfCount = ceil(nAxis / 2);
if secondHalf
    index = (nAxis - halfCount + 1):nAxis;
else
    index = 1:halfCount;
end

for i = 1:numel(setNames)
    field = matlab.lang.makeValidName(setNames{i} + "_set");
    if isfield(payload.setchannels, field)
        payload.setchannels.(field) = sliceAxis(payload.setchannels.(field), index, nAxis);
    end
end

if isfield(payload, "channels")
    channelNames = fieldnames(payload.channels);
    for i = 1:numel(channelNames)
        field = channelNames{i};
        payload.channels.(field) = sliceAxis(payload.channels.(field), index, nAxis);
    end
end

if isfield(payload, "data") && iscell(payload.data) && isfield(loop1, "getchan")
    getCount = numel(loopSetNames(struct("setchan", loop1.getchan)));
    for i = 1:min(getCount, numel(payload.data))
        payload.data{i} = sliceAxis(payload.data{i}, index, nAxis);
    end
end

if isfield(payload.scan.loops(1), "npoints")
    payload.scan.loops(1).npoints = numel(index);
end

end

function [argsOut, secondHalf] = parseInputs(varargin)
argsOut = varargin;
secondHalf = false;

idx = 1;
while idx <= numel(argsOut)
    key = argsOut{idx};
    if (ischar(key) || isstring(key)) && strcmpi(string(key), "secondHalf")
        if idx == numel(argsOut)
            error("Missing value for option secondHalf.");
        end
        secondHalf = logical(argsOut{idx + 1});
        argsOut(idx:(idx + 1)) = [];
        continue;
    end
    idx = idx + 1;
end

if numel(argsOut) >= 4 && islogicalScalar(argsOut{4})
    secondHalf = logical(argsOut{4});
    argsOut(4) = [];
elseif numel(argsOut) >= 3 && islogicalScalar(argsOut{3}) && ...
        (numel(argsOut) == 3 || ischar(argsOut{4}) || isstring(argsOut{4}))
    secondHalf = logical(argsOut{3});
    argsOut(3) = [];
elseif numel(argsOut) == 2 && islogicalScalar(argsOut{2})
    secondHalf = logical(argsOut{2});
    argsOut(2) = [];
end
end

function tf = islogicalScalar(v)
tf = islogical(v) && isscalar(v);
end

function setNames = loopSetNames(loopDef)
raw = loopDef.setchan;
if isempty(raw)
    setNames = {};
elseif iscell(raw)
    setNames = raw;
elseif isstring(raw)
    setNames = cellstr(raw(:).');
else
    setNames = {raw};
end
for i = 1:numel(setNames)
    if isstring(setNames{i})
        setNames{i} = char(setNames{i});
    end
end
end

function out = sliceAxis(in, index, nAxis)
out = in;
if isnumeric(in) || islogical(in)
    if isvector(in) && numel(in) == nAxis
        if isrow(in)
            out = in(index);
        else
            out = in(index, :);
        end
    elseif ndims(in) >= 2 && size(in, 2) == nAxis
        out = in(:, index, :);
    end
end
end
