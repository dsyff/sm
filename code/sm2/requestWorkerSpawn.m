function requestWorkerSpawn(varargin)
%REQUESTWORKERSPAWN Request the client to spawn a pool worker task.
%
% Intended for code running on the measurement engine worker. The engine
% installs a function handle named "sm_spawnOnClient" in the worker base
% workspace; this helper calls it.
%
% Usage:
%   requestWorkerSpawn(@fcn, nOut, arg1, arg2, ...)
%   requestWorkerSpawn(requestedBy, @fcn, nOut, arg1, arg2, ...)

if nargin < 2
    error("requestWorkerSpawn:InvalidUsage", ...
        "Usage: requestWorkerSpawn(@fcn, nOut, ...) or requestWorkerSpawn(requestedBy, @fcn, nOut, ...).");
end

requestedBy = "";

if (isstring(varargin{1}) && isscalar(varargin{1})) || ischar(varargin{1})
    if nargin < 3
        error("requestWorkerSpawn:InvalidUsage", "Usage: requestWorkerSpawn(requestedBy, @fcn, nOut, ...).");
    end
    requestedBy = string(varargin{1});
    fcn = varargin{2};
    nOut = varargin{3};
    args = varargin(4:end);
else
    fcn = varargin{1};
    nOut = varargin{2};
    args = varargin(3:end);
end

if ~isa(fcn, "function_handle")
    error("requestWorkerSpawn:InvalidFcn", "Function argument must be a function_handle.");
end
nOut = double(nOut);
if ~(isscalar(nOut) && isfinite(nOut) && nOut >= 0 && mod(nOut, 1) == 0)
    error("requestWorkerSpawn:InvalidNOut", "nOut must be a nonnegative integer.");
end

if isempty(getCurrentTask())
    error("requestWorkerSpawn:NotOnWorker", "requestWorkerSpawn can only be called from a worker task.");
end

spawnOnClient = [];
try
    spawnOnClient = evalin("base", "sm_spawnOnClient");
catch
end
if isempty(spawnOnClient) || ~isa(spawnOnClient, "function_handle")
    error("requestWorkerSpawn:Unavailable", "sm_spawnOnClient is not available in the worker base workspace.");
end

spawnOnClient(requestedBy, fcn, nOut, args{:});
end

