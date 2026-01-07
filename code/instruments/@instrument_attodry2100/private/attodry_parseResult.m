function varargout = attodry_parseResult(data, expectedCount, operation)
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
    data (1, 1) struct
    expectedCount (1, 1) double {mustBeInteger, mustBePositive}
    operation (1, 1) string {mustBeNonzeroLengthText}
end

if ~isfield(data, "result")
    if isfield(data, "error")
        error("instrument_attodry2100:JsonRpcError", ...
            "%s returned JSON-RPC error with no result field. Response:\n%s", ...
            operation, string(jsonencode(data.error)));
    end
    error("instrument_attodry2100:MalformedResponse", ...
        "%s returned response with no result field. Response:\n%s", ...
        operation, string(jsonencode(data)));
end

r = data.result;
rCount = numel(r);

% Extract errorNumber from first element.
if rCount < 1
    error("instrument_attodry2100:MalformedResponse", ...
        "%s expected at least 1 result value (errorNumber) but received none. Response:\n%s", ...
        operation, string(jsonencode(data)));
end

if iscell(r)
    errorNumber = r{1};
else
    errorNumber = r(1);
end

% Thomas edit: handle cases where the vendor API returns nested cells.
if iscell(errorNumber)
    errorNumber = errorNumber{1};
end
errorNumber = double(errorNumber);

% If we expect additional values, ensure they exist on success.
if expectedCount > 1 && rCount < expectedCount
    if errorNumber == 0
        error("instrument_attodry2100:MissingReturnValue", ...
            "%s expected %d result values but received %d despite errorNumber==0. Response:\n%s", ...
            operation, expectedCount, rCount, string(jsonencode(data)));
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

    % Unwrap nested cells if present.
    if iscell(v)
        v = v{1};
    end

    varargout{k} = v;
end

end


