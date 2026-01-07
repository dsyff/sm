function varargout = attodry_parseResult(rawOrDecoded, expectedCount, operation)
% attodry_parseResult
%
% Thomas edit (sm-dev): These wrapper .m files are copied from the
% manufacturer's CRYO2100 MATLAB API. The vendor version assumes
% data.result always contains all expected elements (e.g. result(2) exists).
% In practice, on errors the response may only include result(1) (error code).
% This helper makes all wrappers robust to:
%   - cell vs numeric result payloads
%   - missing return values when an error occurred
%   - malformed responses that claim success but omit expected values

arguments
    rawOrDecoded
    expectedCount (1, 1) double {mustBeInteger, mustBePositive}
    operation (1, 1) string {mustBeNonzeroLengthText}
end

% Thomas edit (sm-dev): decode JSON inside this helper so wrappers can pass
% the raw line from readline(tcp). Always include the raw JSON when errors
% indicate malformed/unexpected format.
rawJson = "";
if isstruct(rawOrDecoded)
    data = rawOrDecoded;
else
    rawJson = string(rawOrDecoded);
    try
        data = jsondecode(rawJson);
    catch ME
        error("instrument_attodry2100:MalformedJson", ...
            "%s could not jsondecode response. Raw JSON:\n%s\n\njsondecode error: %s", ...
            operation, localFormatRawJson(rawJson), string(ME.message));
    end
end

if ~isstruct(data)
    if rawJson == ""
        rawJson = string(jsonencode(data));
    end
    error("instrument_attodry2100:MalformedResponse", ...
        "%s expected decoded JSON to be a struct but received %s. Raw JSON:\n%s", ...
        operation, class(data), localFormatRawJson(rawJson));
end

if ~isfield(data, "result")
    if isfield(data, "error")
        error("instrument_attodry2100:JsonRpcError", ...
            "%s returned JSON-RPC error with no result field. Raw JSON:\n%s", ...
            operation, localRawJson(data, rawJson));
    end
    error("instrument_attodry2100:MalformedResponse", ...
        "%s returned response with no result field. Raw JSON:\n%s", ...
        operation, localRawJson(data, rawJson));
end

r = data.result;
rCount = numel(r);

% Extract errorNumber from first element.
if rCount < 1
    error("instrument_attodry2100:MalformedResponse", ...
        "%s expected at least 1 result value (errorNumber) but received none. Raw JSON:\n%s", ...
        operation, localRawJson(data, rawJson));
end

if iscell(r)
    errorNumber = r{1};
else
    errorNumber = r(1);
end

% Thomas edit (sm-dev): allow scalar cell wrappers (jsondecode artifact), but
% treat nested cells (cell-in-cell) as malformed.
if iscell(errorNumber)
    if numel(errorNumber) ~= 1
        error("instrument_attodry2100:MalformedResponse", ...
            "%s expected scalar errorNumber but received a cell array of size %d. Raw JSON:\n%s", ...
            operation, numel(errorNumber), localRawJson(data, rawJson));
    end
    if iscell(errorNumber{1})
        error("instrument_attodry2100:MalformedResponse", ...
            "%s received nested cell for errorNumber (cell-in-cell). Raw JSON:\n%s", ...
            operation, localRawJson(data, rawJson));
    end
    errorNumber = errorNumber{1};
end
errorNumber = double(errorNumber);

% If we expect additional values, ensure they exist on success.
if expectedCount > 1 && rCount < expectedCount
    if errorNumber == 0
        error("instrument_attodry2100:MissingReturnValue", ...
            "%s expected %d result values but received %d despite errorNumber==0. Raw JSON:\n%s", ...
            operation, expectedCount, rCount, localRawJson(data, rawJson));
    end
end

varargout = cell(1, expectedCount);
varargout{1} = errorNumber;

for k = 2:expectedCount
    if rCount < k
        % On errors, the device may omit return values beyond errorNumber.
        varargout{k} = NaN;
        continue;
    end

    if iscell(r)
        v = r{k};
    else
        v = r(k);
    end

    % Thomas edit (sm-dev): allow scalar cell wrappers, but treat nested cells
    % (cell-in-cell) as malformed since it indicates unexpected JSON structure.
    if iscell(v)
        if numel(v) ~= 1
            error("instrument_attodry2100:MalformedResponse", ...
                "%s expected scalar result(%d) but received a cell array of size %d. Raw JSON:\n%s", ...
                operation, k, numel(v), localRawJson(data, rawJson));
        end
        if iscell(v{1})
            error("instrument_attodry2100:MalformedResponse", ...
                "%s received nested cell for result(%d) (cell-in-cell). Raw JSON:\n%s", ...
                operation, k, localRawJson(data, rawJson));
        end
        v = v{1};
    end

    varargout{k} = v;
end

end

function raw = localRawJson(decoded, rawJson)
% Return the raw JSON when we have it; otherwise fall back to re-encoding.
if rawJson ~= ""
    raw = localFormatRawJson(rawJson);
else
    raw = localFormatRawJson(string(jsonencode(decoded)));
end
end

function out = localFormatRawJson(rawJson)
% Split long, single-line JSON into readable chunks for error messages.
rawJson = string(rawJson);
chunkLen = 240;
if strlength(rawJson) <= chunkLen
    out = rawJson;
    return;
end

n = ceil(double(strlength(rawJson)) / chunkLen);
chunks = strings(n, 1);
for i = 1:n
    a = (i - 1) * chunkLen + 1;
    b = min(i * chunkLen, strlength(rawJson));
    chunks(i) = extractBetween(rawJson, a, b);
end
out = strjoin(chunks, newline);
end


