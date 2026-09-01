function smQueueRefresh()
%SMQUEUEREFRESH Render the independent queue state without raising its view.
%#ok<*GVMIS>

global engine
persistent lastFailure
try
    renderQueue(engine);
    smbridgeUpdateScanRunState();
    lastFailure = "";
catch ME
    failure = string(ME.identifier) + ":" + string(ME.message);
    if isempty(lastFailure) || lastFailure ~= failure
        experimentContext.print("Queue view refresh warning: %s", ME.message);
        lastFailure = failure;
    end
end
end

function renderQueue(engine)
stateOwner = existingState();
if isempty(stateOwner)
    return;
end
state = stateOwner.snapshot();
fig = state.view;
if isempty(fig) || ~isgraphics(fig, "figure")
    return;
end
h = guidata(fig);
if ~isstruct(h) || ~isfield(h, "queue_lbh")
    return;
end
palette = getappdata(fig, "smQueueTheme");

safeLocked = engineIsSafeLocked(engine);
engineActive = validEngine(engine) && engine.isScanInProgress;
wasSafeLocked = strcmp(get(h.safe_overlay, "Visible"), "on");
if safeLocked
    set(h.controls(isgraphics(h.controls)), "Enable", "off");
    set(h.file_menu, "Enable", "off");
    set(h.safe_overlay, "Visible", "on", "Enable", "on");
else
    set(h.safe_overlay, "Visible", "off");
    set(h.controls(isgraphics(h.controls)), "Enable", "on");
    set(h.file_menu, "Enable", "on");
end
if wasSafeLocked ~= safeLocked
    resizeCallback = get(fig, "SizeChangedFcn");
    resizeCallback(fig, []);
end
set(h.content_panels(isgraphics(h.content_panels)), "ForegroundColor", ...
    panelColor(palette, safeLocked));
smbridgeUpdateEditRackMenuState(engineActive || state.queuePhase ~= "idle");
if safeLocked
    renderActionButtons(h, palette);
    account = notificationAccount(engine);
    set(h.notify_account, "String", account, "TooltipString", account);
    return;
end

scanRows = strings(1, numel(state.scans));
for index = 1:numel(state.scans)
    scanRows(index) = scanLabel(state.scans{index}, index);
end
queueRows = strings(1, numel(state.queue));
for index = 1:numel(state.queue)
    queueRows(index) = sprintf("%d  %s", index, itemLabel(state.queue{index}));
end
renderList(h.scans_lbh, scanRows, state.selectedScanIndex, "No scans loaded");
renderList(h.queue_lbh, queueRows, state.selectedQueueIndex, "Queue is empty");

renderDraft(h.qtxt_eth, state.draft);
renderSource(h, state.source, palette);

[status, statusTooltip] = queueStatus(state);
set(h.status_sth, "String", status, "TooltipString", statusTooltip);
account = notificationAccount(engine);
set(h.notify_account, "String", account, "TooltipString", account);

set(h.openscans, "Enable", "on");
set(h.savescans, "Enable", onOff(~isempty(state.scans)));
set(h.scans_lbh, "Enable", interactiveState(~isempty(state.scans)));
set(h.queue_lbh, "Enable", interactiveState(~isempty(state.queue)));

sourceReady = (state.source == "scans" && ~isempty(state.selectedScanIndex)) ...
    || (state.source == "raw" && strlength(strip(state.draft)) > 0);
afterReady = sourceReady && (isempty(state.queue) || ~isempty(state.selectedQueueIndex));
set(h.insert_top_pbh, "Enable", onOff(sourceReady));
set(h.insert_after_pbh, "Enable", onOff(afterReady));
set(h.insert_end_pbh, "Enable", onOff(sourceReady));

queueIndex = state.selectedQueueIndex;
hasQueueSelection = ~isempty(queueIndex);
set(h.moveup_pbh, "Enable", onOff(hasQueueSelection && queueIndex > 1));
set(h.movedown_pbh, "Enable", onOff(hasQueueSelection && queueIndex < numel(state.queue)));
set(h.removequeue_pbh, "Enable", onOff(hasQueueSelection));

set(h.run_pbh, "Enable", onOff(state.queuePhase == "idle" ...
    && ~isempty(state.queue) && ~engineActive));
stopAfter = state.stopAfterCurrent || state.queuePhase == "stoppingAfterCurrent";
set(h.stopqueue_pbh, "String", stopQueueLabel(stopAfter));
stopQueueEnabled = ismember(state.queuePhase, ...
    ["runningScan", "runningRaw", "betweenItems", "finalizing"]) && ~state.stopAfterCurrent;
set(h.stopqueue_pbh, "Enable", onOff(stopQueueEnabled));
stopNowEnabled = (state.queuePhase == "runningScan" ...
    || state.queuePhase == "stoppingAfterCurrent") ...
    && ~isempty(state.runningItem) && state.runningItem.kind == "scan" ...
    && (~validEngine(engine) || engine.activeRunPhase ~= "finalizing");
set(h.stopnow_pbh, "Enable", onOff(stopNowEnabled));
renderActionButtons(h, palette);

end

function state = existingState()
global smaux
state = [];
if isstruct(smaux) && isfield(smaux, "queueState") ...
        && isa(smaux.queueState, "smQueueState") && isvalid(smaux.queueState)
    state = smaux.queueState;
end
end

function renderList(handle, rows, selectedIndex, placeholder)
fig = ancestor(handle, "figure");
foreground = get(fig, "DefaultUicontrolForegroundColor");
if isempty(rows)
    muted = 0.55 * foreground + 0.45 * get(handle, "BackgroundColor");
    set(handle, "Max", 2, "Min", 0, "Value", [], "ListboxTop", 1, ...
        "String", {char(placeholder)}, ...
        "TooltipString", "", "ForegroundColor", muted);
    return;
end
set(handle, "Max", 2, "Min", 0, "Value", 1, "ListboxTop", 1);
set(handle, "String", cellstr(rows(:)), "ForegroundColor", foreground);
if isempty(selectedIndex)
    set(handle, "Value", []);
    tooltip = "";
else
    set(handle, "Value", selectedIndex, "ListboxTop", selectedIndex);
    set(handle, "Max", 1);
    tooltip = rows(selectedIndex);
end
set(handle, "TooltipString", tooltip);
end

function renderSource(h, source, palette)
if source == "raw"
    set(h.commands_panel, "BorderWidth", 2, "HighlightColor", palette.activeBorder);
    set(h.scans_panel, "BorderWidth", 1, "HighlightColor", palette.inactiveBorder);
    set(h.insert_source_sth, "String", "Source: Raw");
else
    set(h.scans_panel, "BorderWidth", 2, "HighlightColor", palette.activeBorder);
    set(h.commands_panel, "BorderWidth", 1, "HighlightColor", palette.inactiveBorder);
    set(h.insert_source_sth, "String", "Source: Scans");
end
end

function renderDraft(handle, draft)
prompt = "Enter MATLAB commands...";
promptVisible = isequal(getappdata(handle, "smQueuePromptVisible"), true);
fig = ancestor(handle, "figure");
focused = isgraphics(fig, "figure") && isequal(get(fig, "CurrentObject"), handle);
if focused && ~promptVisible
    set(handle, "ForegroundColor", get(fig, "DefaultUicontrolForegroundColor"));
    return;
end
if strlength(draft) == 0
    if ~promptVisible || rawText(get(handle, "String")) ~= prompt
        set(handle, "String", prompt);
    end
    foreground = get(fig, "DefaultUicontrolForegroundColor");
    set(handle, "ForegroundColor", 0.55 * foreground + 0.45 * get(handle, "BackgroundColor"));
    setappdata(handle, "smQueuePromptVisible", true);
    return;
end
current = rawText(get(handle, "String"));
if promptVisible || current ~= draft
    set(handle, "String", char(draft));
end
set(handle, "ForegroundColor", get(fig, "DefaultUicontrolForegroundColor"));
setappdata(handle, "smQueuePromptVisible", false);
end

function [status, tooltip] = queueStatus(state)
if isempty(state.runningItem)
    name = "";
else
    name = state.runningItem.label;
end
switch state.queuePhase
    case {"runningScan", "runningRaw"}
        status = "Running: " + name;
    case "stoppingAfterCurrent"
        status = "Stopping After Current: " + name;
    case "stoppingNow"
        status = "Stopping Now: " + name;
    case "finalizing"
        status = "Finalizing: " + name;
    otherwise
        status = "Idle";
end
tooltip = status;
end

function label = scanLabel(scan, index)
if isstruct(scan) && isfield(scan, "name") && ~isempty(scan.name)
    label = string(scan.name);
elseif isobject(scan) && isprop(scan, "name") && strlength(string(scan.name)) > 0
    label = string(scan.name);
else
    label = "Scan " + index;
end
if ~isscalar(label)
    label = join(label(:), " ");
end
end

function label = itemLabel(item)
if isstruct(item) && isscalar(item) && isfield(item, "eval") && ~isfield(item, "loops")
    text = rawText(item.eval);
    lines = splitlines(text);
    lines = lines(strlength(strip(lines)) > 0);
    if isempty(lines)
        label = "[CMD]";
    else
        label = "[CMD] " + lines(1);
    end
else
    label = scanLabel(item, 1);
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
    text = "";
end
end

function account = notificationAccount(engine)
account = "Account not provided";
if ~validEngine(engine)
    return;
end
settings = engine.slack_notification_settings;
if isfield(settings, "account_email") && strlength(strip(string(settings.account_email))) > 0
    account = strip(string(settings.account_email));
end
end

function locked = engineIsSafeLocked(engine)
locked = validEngine(engine) && engine.activeRunMode == "safe";
end

function valid = validEngine(engine)
valid = ~isempty(engine) && isa(engine, "measurementEngine") && isvalid(engine);
end

function value = onOff(condition)
if condition
    value = "on";
else
    value = "off";
end
end

function value = interactiveState(condition)
if condition
    value = "on";
else
    value = "inactive";
end
end

function value = stopQueueLabel(stopping)
if stopping
    value = "Stopping After Current...";
else
    value = "Stop Queue";
end
end

function color = panelColor(palette, dimmed)
if dimmed
    color = palette.dimmedPanelText;
else
    color = palette.panelText;
end
end

function renderActionButtons(h, palette)
renderActionButton(h.run_pbh, palette.start, palette);
renderActionButton(h.stopqueue_pbh, palette.stopQueue, palette);
renderActionButton(h.stopnow_pbh, palette.stopNow, palette);
end

function renderActionButton(handle, enabledColor, palette)
if strcmp(get(handle, "Enable"), "on")
    set(handle, "BackgroundColor", enabledColor, "ForegroundColor", palette.actionText);
else
    set(handle, "BackgroundColor", palette.disabledAction, ...
        "ForegroundColor", palette.disabledActionText);
end
end
