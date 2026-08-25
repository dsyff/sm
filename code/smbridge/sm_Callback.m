function varargout = sm_Callback(what, varargin)
%SM_CALLBACK Queue GUI controller and compatibility dispatcher.
%#ok<*GVMIS>

name = string(what);
if ~isscalar(name) || strlength(name) == 0
    error("sm_Callback:InvalidAction", "A scalar callback action is required.");
end
if nargout > 0
    [varargout{1:nargout}] = feval(char(name), varargin{:});
else
    feval(char(name), varargin{:});
end
end

function Open(~)
global bridge
if ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath") ...
        && strlength(string(bridge.experimentRootPath)) == 0
    bridge.experimentRootPath = pwd;
end
smQueueRefresh();
end

function Close(fig)
global smaux
state = queueState();
if nargin < 1 || isempty(fig)
    fig = state.view();
end
if isempty(fig) || ~isgraphics(fig, "figure")
    return;
end
h = guidata(fig);
if isstruct(h) && isfield(h, "qtxt_eth") && isgraphics(h.qtxt_eth)
    state.setDraft(readDraft(h.qtxt_eth));
end
state.detachView(fig);
if isstruct(smaux) && isfield(smaux, "sm") && isstruct(smaux.sm) ...
        && isfield(smaux.sm, "figure1") && isequal(smaux.sm.figure1, fig)
    smaux.sm = struct();
end
delete(fig);
end

function UpdateToGUI
smQueueRefresh();
end

function ViewMouseDown
if blockedBySafeMode()
    return;
end
state = queueState();
fig = state.view();
if isempty(fig) || ~isgraphics(fig, "figure")
    return;
end
h = guidata(fig);
target = hittest(fig);
if isempty(target) || ~isgraphics(target)
    return;
end
panel = ancestor(target, "uipanel");
if target == h.qtxt_eth || target == h.commands_panel || panel == h.commands_panel
    state.setSource("raw");
    smQueueRefresh();
    if isgraphics(h.qtxt_eth) && isequal(getappdata(h.qtxt_eth, "smQueuePromptVisible"), true)
        set(h.qtxt_eth, "String", "", "ForegroundColor", [0 0 0]);
        setappdata(h.qtxt_eth, "smQueuePromptVisible", false);
    end
elseif target == h.scans_lbh || target == h.scans_panel || panel == h.scans_panel
    state.setSource("scans");
    smQueueRefresh();
end
end

function SelectSource(source)
if blockedBySafeMode()
    return;
end
queueState().setSource(source);
smQueueRefresh();
end

function Scans
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if isempty(h)
    return;
end
snapshot = state.snapshot();
if isempty(snapshot.scans)
    return;
end
value = get(h.scans_lbh, "Value");
if isempty(value)
    state.select("scans", []);
else
    state.select("scans", value(end));
end
if strcmp(get(h.figure1, "SelectionType"), "open")
    EditScan2();
else
    smQueueRefresh();
end
end

function Queue
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if isempty(h)
    return;
end
snapshot = state.snapshot();
if isempty(snapshot.queue)
    return;
end
value = get(h.queue_lbh, "Value");
if isempty(value)
    state.select("queue", []);
else
    state.select("queue", value(end));
end
if strcmp(get(h.figure1, "SelectionType"), "open")
    EditScan();
else
    smQueueRefresh();
end
end

function Qtxt
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if isempty(h)
    return;
end
state.setSource("raw");
state.setDraft(readDraft(h.qtxt_eth));
smQueueRefresh();
end

function RawKeyPress
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if isempty(h)
    return;
end
state.setSource("raw");
if isequal(getappdata(h.qtxt_eth, "smQueuePromptVisible"), true)
    set(h.qtxt_eth, "String", "", "ForegroundColor", [0 0 0]);
    setappdata(h.qtxt_eth, "smQueuePromptVisible", false);
end
end

function InsertTop
insertAt("top");
end

function InsertAfter
insertAt("after");
end

function InsertEnd
insertAt("end");
end

function insertAt(where)
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if ~isempty(h) && state.snapshot().source == "raw"
    state.setDraft(readDraft(h.qtxt_eth));
end
state.insert(where);
smQueueRefresh();
end

function Enqueue
InsertAfter();
end

function TXTenqueue
if blockedBySafeMode()
    return;
end
[h, state] = viewHandles();
if isempty(h)
    return;
end
state.setSource("raw");
state.setDraft(readDraft(h.qtxt_eth));
state.insert("after");
smQueueRefresh();
end

function MoveUp
movePending("up");
end

function MoveDown
movePending("down");
end

function movePending(direction)
if blockedBySafeMode()
    return;
end
queueState().move(direction);
smQueueRefresh();
end

function RemoveQueue
if blockedBySafeMode()
    return;
end
queueState().remove("queue");
smQueueRefresh();
end

function RemoveScan
if blockedBySafeMode()
    return;
end
queueState().remove("scans");
smQueueRefresh();
end

function EditScan
global smscan
if blockedBySafeMode()
    return;
end
state = queueState();
[edited, entry] = state.editQueued();
if ~edited
    return;
end
if entry.kind == "raw"
    smQueueRefresh();
    return;
end
smscan = entry.payload;
smgui_small();
smQueueRefresh();
end

function EditScan2
global smscan
if blockedBySafeMode()
    return;
end
state = queueState();
[found, entry] = state.selected("scans");
if ~found
    return;
end
smscan = entry.payload;
smgui_small();
smQueueRefresh();
end

function QueueKey(event)
if blockedBySafeMode()
    return;
end
key = string(event.Key);
if key == "delete"
    RemoveQueue();
elseif ismember(key, ["return", "enter"])
    EditScan();
elseif hasControl(event) && key == "uparrow"
    MoveUp();
elseif hasControl(event) && key == "downarrow"
    MoveDown();
end
end

function ScansKey(event)
if blockedBySafeMode()
    return;
end
key = string(event.Key);
if key == "delete"
    RemoveScan();
elseif ismember(key, ["return", "enter"])
    EditScan2();
end
end

function OpenScans
if blockedBySafeMode()
    return;
end
choice = questdlg("Load scans from folder or files?", "Open Scans", ...
    "Folder", "Files", "Cancel", "Files");
if strcmp(choice, "Folder")
    folder = uigetdir;
    if isequal(folder, 0)
        return;
    end
    listing = dir(fullfile(folder, "*.mat"));
    listing = listing(~[listing.isdir]);
    fileList = string(fullfile(folder, {listing.name}));
elseif strcmp(choice, "Files")
    [files, folder] = uigetfile("*.mat", "Select Scan File(s)", "MultiSelect", "on");
    if isequal(files, 0)
        return;
    end
    fileList = string(fullfile(folder, cellstr(string(files))));
else
    return;
end
fileList = sortPaths(fileList);

accepted = cell(1, 0);
rejected = 0;
for file = fileList
    try
        payload = load(file);
    catch
        rejected = rejected + 1;
        continue;
    end
    [candidates, supported] = payloadScans(payload);
    if ~supported
        rejected = rejected + 1;
        continue;
    end
    for index = 1:numel(candidates)
        try
            candidate = candidates{index};
            valid = isstruct(candidate) && isscalar(candidate) && isfield(candidate, "loops");
            if valid
                candidate = smscanSanitizeForBridge(candidate);
                valid = ~isempty(candidate);
            end
        catch
            valid = false;
        end
        if ~valid
            rejected = rejected + 1;
            continue;
        end
        accepted{end + 1} = candidate; %#ok<AGROW>
    end
end

experimentContext.print("Loaded %d scans; rejected %d inputs.", numel(accepted), rejected);
if isempty(accepted)
    errordlg("No valid scans were found.", "No Valid Scans", "modal");
    return;
end
queueState().appendScans(accepted, true);
smQueueRefresh();
end

function SaveScans
if blockedBySafeMode()
    return;
end
snapshot = queueState().snapshot();
scans = snapshot.scans;
if isempty(scans)
    return;
end
baseFolder = fullfile(experimentRoot(), ...
    "scans_" + string(datetime("now", "Format", "yyyyMMdd_HHmmss")));
targetFolder = uniqueFolder(baseFolder);
written = 0;
try
    [created, message] = mkdir(targetFolder);
    if ~created
        error("sm:CreateExportFolderFailed", "Could not create %s (%s).", targetFolder, message);
    end
    for index = 1:numel(scans)
        smscan = normalizedScanForSave(scans{index});
        baseName = exportName(smscan, index);
        output = uniqueMatFile(targetFolder, baseName);
        save(output, "smscan");
        written = written + 1;
    end
catch ME
    report = getReport(ME, "extended", "hyperlinks", "off");
    experimentContext.print("Saved %d of %d scans to %s before failure.%s%s", ...
        written, numel(scans), targetFolder, newline, report);
    errordlg(sprintf("Saved %d of %d scans before failure.\n\n%s", ...
        written, numel(scans), ME.message), "Save Scans Failed", "modal");
    return;
end
experimentContext.print("Saved %d scans to %s.", written, targetFolder);
end

function SavePath
if blockedBySafeMode()
    return;
end
picked = uigetdir;
if isequal(picked, 0)
    return;
end
root = experimentRoot();
picked = string(picked);
if startsWith(picked, root, "IgnoreCase", true)
    relative = extractAfter(picked, strlength(root));
    if startsWith(relative, filesep)
        relative = extractAfter(relative, 1);
    end
    if strlength(relative) == 0
        relative = "data";
    end
else
    [~, relative] = fileparts(picked);
    relative = string(relative);
    if strlength(relative) == 0
        relative = "data";
    end
end
target = fullfile(root, relative);
smdatapathUpdateGlobalState("main", target);
smdatapathApplyStateToGui("main");
end

function RunNum
if blockedBySafeMode()
    return;
end
[h, ~] = viewHandles();
if isempty(h)
    return;
end
text = string(get(h.run_eth, "String"));
if strlength(strip(text)) == 0
    value = [];
else
    value = str2double(text);
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value > 999
        errordlg("Please enter a number in [0, 999].", "Bad Run Number", "modal");
        value = [];
    end
end
smrunUpdateGlobalState("main", value);
smrunApplyStateToGui("main");
end

function PPTauto
if blockedBySafeMode()
    return;
end
[h, ~] = viewHandles();
if isempty(h)
    return;
end
[~, file] = smpptGetState();
smpptUpdateGlobalState("main", logical(get(h.pptauto_cbh, "Value")), file);
smpptApplyStateToGui("main");
end

function PPTFile
if blockedBySafeMode()
    return;
end
[enabled, current] = smpptGetState();
if isempty(current)
    current = fullfile(experimentRoot(), "log.ppt");
end
[file, folder] = uiputfile("*.ppt", "Append to Presentation", current);
if isequal(file, 0)
    return;
end
[~, name, extension] = fileparts(file);
if strlength(string(extension)) == 0
    extension = ".ppt";
end
smpptUpdateGlobalState("main", enabled, fullfile(folder, string(name) + string(extension)));
smpptApplyStateToGui("main");
end

function EditRack
global engine
if blockedBySafeMode() || smbridgeQueueRunnerActive() ...
        || (validEngine(engine) && engine.isScanInProgress)
    return;
end
smeditrack();
end

function Start
global engine
if blockedBySafeMode() || ~validEngine(engine)
    return;
end
state = queueState();
snapshot = state.snapshot();
if snapshot.queuePhase ~= "idle" || isempty(snapshot.queue) || engine.isScanInProgress
    return;
end
if ~state.beginRun()
    return;
end

cleanup = onCleanup(@() finishRunner(state));
smbridgeUpdateEditRackMenuState(true);
smQueueRefresh();
drawnow;

while true
    [started, item] = state.startNext();
    if ~started
        break;
    end
    smQueueRefresh();
    drawnow limitrate nocallbacks;
    outcome = "complete";
    itemError = MException.empty;
    try
        if item.kind == "raw"
            executeRaw(item.payload);
        else
            metadata = executeScan(item.payload);
            if isfield(metadata, "stopRequested") && logical(metadata.stopRequested)
                outcome = "stopped";
            end
        end
    catch itemError
        outcome = "error";
    end
    shouldContinue = state.finishCurrent(outcome);
    smQueueRefresh();
    if ~isempty(itemError)
        reportQueueItemError(itemError, item.label);
    end
    drawnow;
    if ~shouldContinue
        break;
    end
end
end

function Run
Start();
end

function StopQueue
if blockedBySafeMode()
    return;
end
queueState().requestStopAfter();
smQueueRefresh();
end

function StopNow
global engine
if blockedBySafeMode()
    return;
end
state = queueState();
snapshot = state.snapshot();
if ismember(snapshot.queuePhase, ["finalizing", "betweenItems"])
    state.requestStopNow();
    smQueueRefresh();
    return;
end
if ~ismember(snapshot.queuePhase, ["runningScan", "stoppingAfterCurrent"]) ...
        || isempty(snapshot.runningItem) || snapshot.runningItem.kind ~= "scan"
    return;
end
if validEngine(engine) && engine.activeRunPhase == "finalizing"
    state.requestStopAfter();
    state.setFinalizing();
    smQueueRefresh();
    return;
end
choice = questdlg( ...
    "Stop the current scan now? Finish actions will run, partial data will be saved, and the queue will stop.", ...
    "Stop Current Scan?", "Stop Now", "Cancel", "Cancel");
if ~strcmp(choice, "Stop Now")
    return;
end
action = state.requestStopNow();
if action == "stopNow" && validEngine(engine)
    accepted = engine.requestScanStop("Queue Stop Now requested by user.");
    if ~accepted && engine.activeRunPhase == "finalizing"
        state.setFinalizing();
        state.requestStopAfter();
    end
end
smQueueRefresh();
end

function finishRunner(state)
state.endRun();
smbridgeUpdateEditRackMenuState(false);
smQueueRefresh();
end

function metadata = executeScan(scan)
global engine
scanName = itemLabel(scan);
if startsWith(scanName, "[CMD]")
    scanName = "scan";
end
if isstruct(scan) && isfield(scan, "ppt")
    scan = rmfield(scan, "ppt");
end
[~, metadata] = engine.run(scan, "", "turbo");
stopped = isfield(metadata, "stopRequested") && logical(metadata.stopRequested);
complete = isfield(metadata, "isComplete") && logical(metadata.isComplete);
if complete || stopped
    sendNotification(scanName, metadata, stopped);
end
end

function sendNotification(scanName, metadata, stopped)
global engine
settings = engine.slack_notification_settings;
try
    userId = smnotifySlackScanComplete(scanName, metadata.pngFile, metadata.filename, ...
        metadata.duration, settings, stopped, string(metadata.stopMessage));
    if strlength(string(userId)) > 0 && isfield(settings, "account_email")
        engine.cacheSlackNotificationUserId(string(settings.account_email), string(userId));
    end
catch ME
    experimentContext.print("Slack notification warning: notification for scan %s failed (%s).", ...
        scanName, ME.message);
end
end

function executeRaw(payload)
text = rawText(payload.eval);
lines = splitlines(text);
for index = 1:numel(lines)
    evalin("base", char(lines(index)));
end
end

function reportQueueItemError(ME, label)
report = getReport(ME, "extended", "hyperlinks", "off");
experimentContext.print("%s", report);
errordlg(sprintf("%s\n\n%s", label, ME.message), "Queue Item Error", "modal");
end

function [h, state] = viewHandles()
state = queueState();
fig = state.view();
if isempty(fig) || ~isgraphics(fig, "figure")
    h = [];
else
    h = guidata(fig);
end
end

function state = queueState()
state = smQueueState.get();
end

function blocked = blockedBySafeMode()
global engine
blocked = validEngine(engine) && engine.activeRunMode == "safe";
end

function valid = validEngine(engine)
valid = ~isempty(engine) && isa(engine, "measurementEngine") && isvalid(engine);
end

function draft = readDraft(handle)
if isequal(getappdata(handle, "smQueuePromptVisible"), true)
    draft = "";
else
    draft = rawText(get(handle, "String"));
end
end

function text = rawText(value)
if ischar(value)
    if isempty(value)
        text = "";
    elseif isrow(value)
        text = string(value);
    else
        text = join(string(cellstr(value)), newline);
    end
elseif isstring(value) || iscellstr(value)
    text = join(string(value(:)), newline);
else
    error("sm:InvalidRawCommand", "Raw command text must be char, string, or cellstr.");
end
end

function tf = hasControl(event)
if isstruct(event)
    tf = isfield(event, "Modifier") && any(string(event.Modifier) == "control");
else
    tf = isprop(event, "Modifier") && any(string(event.Modifier) == "control");
end
end

function paths = sortPaths(paths)
paths = paths(:);
if isempty(paths)
    return;
end
[~, order] = sortrows([lower(paths) paths], [1 2]);
paths = paths(order).';
end

function [scans, supported] = payloadScans(payload)
scans = cell(1, 0);
supported = true;
if isfield(payload, "smscan") && isstruct(payload.smscan)
    scans = reshape(num2cell(payload.smscan), 1, []);
elseif isfield(payload, "scan") && isstruct(payload.scan)
    scans = reshape(num2cell(payload.scan), 1, []);
elseif isfield(payload, "scans") && iscell(payload.scans)
    scans = reshape(payload.scans, 1, []);
elseif isfield(payload, "scans") && isstruct(payload.scans)
    scans = reshape(num2cell(payload.scans), 1, []);
else
    supported = false;
end
end

function scan = normalizedScanForSave(scan)
if ~isstruct(scan) || ~isscalar(scan)
    error("sm:InvalidLibraryScan", "Every library entry must be a scalar scan struct.");
end
if isfield(scan, "consts")
    scan.consts = measurementScan.normalizeConsts(scan.consts);
end
if ~isfield(scan, "finish")
    scan.finish = [];
end
scan.finish = measurementScan.normalizeConsts(scan.finish, "scan.finish");
end

function name = exportName(scan, index)
name = "scan_" + index;
if isfield(scan, "name") && strlength(string(scan.name)) > 0
    name = string(scan.name);
end
if ~isscalar(name)
    name = join(name(:), " ");
end
name = regexprep(name, '[\\/:*?"<>|.]', "_");
if strlength(name) == 0
    name = "scan_" + index;
end
end

function output = uniqueMatFile(folder, baseName)
output = fullfile(folder, baseName + ".mat");
suffix = 0;
while isfile(output)
    suffix = suffix + 1;
    output = fullfile(folder, baseName + " (" + suffix + ").mat");
end
end

function folder = uniqueFolder(baseFolder)
folder = string(baseFolder);
suffix = 0;
while isfolder(folder) || isfile(folder)
    suffix = suffix + 1;
    folder = string(baseFolder) + " (" + suffix + ")";
end
end

function root = experimentRoot()
global bridge
root = string(pwd);
if ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
    if strlength(string(bridge.experimentRootPath)) == 0
        bridge.experimentRootPath = pwd;
    end
    root = string(bridge.experimentRootPath);
end
end

function label = itemLabel(item)
if isstruct(item) && isscalar(item) && isfield(item, "eval") && ~isfield(item, "loops")
    lines = splitlines(rawText(item.eval));
    lines = lines(strlength(strip(lines)) > 0);
    if isempty(lines)
        label = "[CMD]";
    else
        label = "[CMD] " + lines(1);
    end
elseif isstruct(item) && isfield(item, "name") && strlength(string(item.name)) > 0
    label = string(item.name);
elseif isobject(item) && isprop(item, "name") && strlength(string(item.name)) > 0
    label = string(item.name);
else
    label = "Scan";
end
if ~isscalar(label)
    label = join(label(:), " ");
end
end
