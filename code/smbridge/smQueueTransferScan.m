function added = smQueueTransferScan(scan, destination)
%SMQUEUETRANSFERSCAN Transfer a scan and attach/refresh the queue view.
%#ok<*GVMIS>

global engine

destination = string(destination);
if ~isscalar(destination) || ~ismember(destination, ["scans", "queue"])
    error("smQueueTransferScan:InvalidDestination", "Destination must be scans or queue.");
end
if isempty(engine) || ~isa(engine, "measurementEngine") || ~isvalid(engine)
    error("sm:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
end
if engine.activeRunMode == "safe"
    added = false;
    return;
end
if ~isstruct(scan) || ~isscalar(scan) || ~isfield(scan, "loops")
    error("smQueueTransferScan:InvalidScan", "Transferred scan must be a scalar scan struct with loops.");
end

if isfield(scan, "consts")
    scan.consts = measurementScan.normalizeConsts(scan.consts);
end
if ~isfield(scan, "finish")
    scan.finish = [];
end
scan.finish = measurementScan.normalizeConsts(scan.finish, "scan.finish");
scan = smscanSanitizeForBridge(scan);
if isempty(scan)
    error("smQueueTransferScan:InvalidScan", "The scan is not valid for the active rack.");
end

state = smQueueState.get();
if destination == "scans"
    state.appendScans({scan}, true);
else
    state.appendPending({scan}, true);
end
added = true;

if isempty(state.view())
    sm();
else
    smQueueRefresh();
end
end
