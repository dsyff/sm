function varargout = sm(varargin)
%SM Create or raise the programmatic queue GUI singleton.
%#ok<*GVMIS>

global engine smaux

if nargin ~= 0
    error("sm:InvalidArguments", "sm does not accept input arguments.");
end
if isempty(engine) || ~isa(engine, "measurementEngine") || ~isvalid(engine)
    error("sm:MissingEngine", "measurementEngine not found. Please run smready(...) first.");
end

smbridgeAddSharedPaths();
smdatapathEnsureGlobals();
smrunEnsureGlobals();
smpptEnsureGlobals();

state = smQueueState.get();
fig = attachedFigure();
if isgraphics(fig, "figure")
    smQueueBindEngine(engine);
    smQueueRefresh();
    figure(fig);
    if nargout > 0
        varargout{1} = fig;
    end
    return;
end

handles = createView();
fig = handles.figure1;
smaux.sm = handles;
guidata(fig, handles);
state.attachView(fig);

smdatapathRegisterGui("main", struct( ...
    "label", handles.datapath_sth, ...
    "tooltipHandle", handles.datapath_sth, ...
    "displayLimit", 40));
smrunRegisterGui("main", struct( ...
    "edit", handles.run_eth, ...
    "tooltipHandle", handles.run_eth));
smpptRegisterGui("main", struct( ...
    "figure", fig, ...
    "checkbox", handles.pptauto_cbh, ...
    "fileLabel", handles.pptfile_sth));

smQueueBindEngine(engine);
sm_Callback("Open", handles);
set(fig, "Visible", "on");

if nargout > 0
    varargout{1} = fig;
end
end

function fig = attachedFigure()
global smaux
fig = gobjects(0);
if isstruct(smaux) && isfield(smaux, "sm") && isstruct(smaux.sm) ...
        && isfield(smaux.sm, "figure1") && isgraphics(smaux.sm.figure1, "figure")
    fig = smaux.sm.figure1;
end
end

function h = createView()
screen = get(groot, "ScreenSize");
width = 924;
height = 800;
x = max(screen(1), screen(1) + floor((screen(3) - width) / 2));
y = max(screen(2), screen(2) + floor((screen(4) - height) / 2));

h.figure1 = figure( ...
    "Name", "Special Measure Queue", ...
    "NumberTitle", "off", ...
    "Tag", "sm_queue", ...
    "MenuBar", "none", ...
    "ToolBar", "none", ...
    "Units", "pixels", ...
    "Position", [x y width height], ...
    "Resize", "on", ...
    "Visible", "off", ...
    "HandleVisibility", "callback", ...
    "Interruptible", "on", ...
    "BusyAction", "cancel", ...
    "CloseRequestFcn", @(src, ~) sm_Callback("Close", src), ...
    "SizeChangedFcn", @resizeView, ...
    "WindowButtonDownFcn", @(~, ~) sm_Callback("ViewMouseDown"));

h.file_menu = uimenu(h.figure1, "Label", "File");
h.openscans = uimenu(h.file_menu, "Label", "Open Scans...", ...
    "Callback", @(~, ~) sm_Callback("OpenScans"));
h.savescans = uimenu(h.file_menu, "Label", "Save Scans", ...
    "Callback", @(~, ~) sm_Callback("SaveScans"));
h.editrack = uimenu(h.file_menu, "Label", "Edit Rack...", ...
    "Separator", "on", "Callback", @(~, ~) sm_Callback("EditRack"));
setappdata(h.editrack, "smEditRackBaseLabel", "Edit Rack...");

h.save_panel = uipanel(h.figure1, "Title", "Save", "FontWeight", "bold", "Units", "pixels");
h.savepath_pbh = button(h.save_panel, "Path...", @(~, ~) sm_Callback("SavePath"));
h.datapath_sth = uicontrol(h.save_panel, "Style", "text", ...
    "HorizontalAlignment", "left");
h.run_label = uicontrol(h.save_panel, "Style", "text", "String", "Run #", ...
    "HorizontalAlignment", "right");
h.run_eth = uicontrol(h.save_panel, "Style", "edit", ...
    "HorizontalAlignment", "center", "Callback", @(~, ~) sm_Callback("RunNum"));

h.ppt_panel = uipanel(h.figure1, "Title", "PowerPoint", "FontWeight", "bold", "Units", "pixels");
h.pptauto_cbh = uicontrol(h.ppt_panel, "Style", "checkbox", ...
    "String", "Log to PowerPoint", ...
    "Callback", @(~, ~) sm_Callback("PPTauto"));
h.pptfile_pbh = button(h.ppt_panel, "File...", @(~, ~) sm_Callback("PPTFile"));
h.pptfile_sth = uicontrol(h.ppt_panel, "Style", "text", ...
    "HorizontalAlignment", "left");

h.notify_panel = uipanel(h.figure1, "Title", "Notifications", "FontWeight", "bold", "Units", "pixels");
h.notify_label = uicontrol(h.notify_panel, "Style", "text", "String", "Slack:", ...
    "HorizontalAlignment", "left");
h.notify_account = uicontrol(h.notify_panel, "Style", "text", ...
    "HorizontalAlignment", "left");

h.schedule_panel = uipanel(h.figure1, "Title", "Schedule", "FontWeight", "bold", "Units", "pixels");
h.scans_panel = uipanel(h.schedule_panel, "Title", "Available Scans", ...
    "FontWeight", "bold", "Units", "pixels", ...
    "ButtonDownFcn", @(~, ~) sm_Callback("SelectSource", "scans"));
h.scans_lbh = uicontrol(h.scans_panel, "Style", "listbox", ...
    "Max", 1, "Min", 0, ...
    "Callback", @(~, ~) sm_Callback("Scans"), ...
    "KeyPressFcn", @(~, event) sm_Callback("ScansKey", event));

h.commands_panel = uipanel(h.schedule_panel, "Title", "Raw Commands", ...
    "FontWeight", "bold", "Units", "pixels", ...
    "ButtonDownFcn", @(~, ~) sm_Callback("SelectSource", "raw"));
h.qtxt_eth = uicontrol(h.commands_panel, "Style", "edit", ...
    "HorizontalAlignment", "left", ...
    "Max", 20, "Min", 0, ...
    "Callback", @(~, ~) sm_Callback("Qtxt"), ...
    "KeyPressFcn", @(~, ~) sm_Callback("RawKeyPress"), ...
    "KeyReleaseFcn", @(~, ~) sm_Callback("Qtxt"));

h.insert_source_sth = uicontrol(h.schedule_panel, "Style", "text", ...
    "String", "Source: Scans", "FontWeight", "bold", ...
    "HorizontalAlignment", "center");
h.insert_top_pbh = button(h.schedule_panel, "Top >>", @(~, ~) sm_Callback("InsertTop"));
h.insert_after_pbh = button(h.schedule_panel, "After >>", @(~, ~) sm_Callback("InsertAfter"));
h.insert_end_pbh = button(h.schedule_panel, "End >>", @(~, ~) sm_Callback("InsertEnd"));

h.queue_panel = uipanel(h.schedule_panel, "Title", "Queue", "FontWeight", "bold", "Units", "pixels");
h.status_sth = uicontrol(h.queue_panel, "Style", "text", "String", "Idle", ...
    "FontWeight", "bold", "HorizontalAlignment", "left");
h.run_pbh = button(h.queue_panel, "Start", @(~, ~) sm_Callback("Start"));
set(h.run_pbh, "FontWeight", "bold", "Interruptible", "on", "BusyAction", "cancel");
h.stopqueue_pbh = button(h.queue_panel, "Stop Queue", @(~, ~) sm_Callback("StopQueue"));
set(h.stopqueue_pbh, "FontWeight", "bold");
h.stopnow_pbh = button(h.queue_panel, "Stop Now", @(~, ~) sm_Callback("StopNow"));
set(h.stopnow_pbh, "FontWeight", "bold");
h.queue_lbh = uicontrol(h.queue_panel, "Style", "listbox", ...
    "Max", 1, "Min", 0, ...
    "Callback", @(~, ~) sm_Callback("Queue"), ...
    "KeyPressFcn", @(~, event) sm_Callback("QueueKey", event));
h.moveup_pbh = button(h.queue_panel, "Move Up", @(~, ~) sm_Callback("MoveUp"));
h.movedown_pbh = button(h.queue_panel, "Move Down", @(~, ~) sm_Callback("MoveDown"));
h.removequeue_pbh = button(h.queue_panel, "Remove", @(~, ~) sm_Callback("RemoveQueue"));

h.safe_overlay = uicontrol(h.schedule_panel, "Style", "text", ...
    "String", "Safe-mode scan active — queue controls disabled", ...
    "FontWeight", "bold", "FontSize", 11, ...
    "Visible", "off");

h.interactive = [h.savepath_pbh; h.run_eth; h.pptauto_cbh; h.pptfile_pbh; ...
    h.scans_lbh; h.qtxt_eth; h.insert_top_pbh; h.insert_after_pbh; h.insert_end_pbh; ...
    h.run_pbh; h.stopqueue_pbh; h.stopnow_pbh; h.queue_lbh; ...
    h.moveup_pbh; h.movedown_pbh; h.removequeue_pbh];
h.content_panels = [h.save_panel; h.ppt_panel; h.notify_panel; h.schedule_panel; ...
    h.scans_panel; h.commands_panel; h.queue_panel];
h.controls = findall(h.figure1, "Type", "uicontrol");

guidata(h.figure1, h);
if isprop(h.figure1, "ThemeChangedFcn")
    set(h.figure1, "ThemeChangedFcn", @applyTheme);
end
applyTheme(h.figure1, []);
resizeView(h.figure1, []);
end

function h = button(parent, label, callback)
h = uicontrol(parent, "Style", "pushbutton", "String", label, ...
    "Callback", callback, "Interruptible", "on", "BusyAction", "cancel");
end

function applyTheme(fig, ~)
h = guidata(fig);
if ~isstruct(h) || ~isfield(h, "run_pbh")
    return;
end
isDark = isprop(fig, "Theme") && strcmp(fig.Theme.BaseColorStyle, "dark");
if isDark
    palette = struct( ...
        "start", [0.22 0.50 0.28], "stopQueue", [0.55 0.38 0.10], ...
        "stopNow", [0.58 0.24 0.24], "actionText", [0.95 0.95 0.95], ...
        "disabledAction", [0.16 0.16 0.16], "disabledActionText", [0.62 0.62 0.62], ...
        "activeBorder", [0.30 0.65 1.00], "inactiveBorder", [0.42 0.42 0.42], ...
        "safeBackground", [0.42 0.27 0.06], "safeText", [1.00 0.86 0.55]);
else
    palette = struct( ...
        "start", [0.60 0.82 0.60], "stopQueue", [0.95 0.77 0.38], ...
        "stopNow", [0.88 0.47 0.47], "actionText", [0.10 0.10 0.10], ...
        "disabledAction", [0.86 0.86 0.86], "disabledActionText", [0.45 0.45 0.45], ...
        "activeBorder", [0.18 0.48 0.78], "inactiveBorder", [0.55 0.55 0.55], ...
        "safeBackground", [1.00 0.91 0.72], "safeText", [0.45 0.20 0.05]);
end
palette.panelText = get(fig, "DefaultUipanelForegroundColor");
palette.dimmedPanelText = 0.5 * (palette.panelText + get(fig, "Color"));
setappdata(fig, "smQueueTheme", palette);
set(h.run_pbh, "BackgroundColor", palette.start, "ForegroundColor", palette.actionText);
set(h.stopqueue_pbh, "BackgroundColor", palette.stopQueue, "ForegroundColor", palette.actionText);
set(h.stopnow_pbh, "BackgroundColor", palette.stopNow, "ForegroundColor", palette.actionText);
set(h.safe_overlay, "BackgroundColor", palette.safeBackground, "ForegroundColor", palette.safeText);
smQueueRefresh();
end

function resizeView(fig, ~)
if ~isgraphics(fig, "figure") || isequal(getappdata(fig, "smQueueResizing"), true)
    return;
end
setappdata(fig, "smQueueResizing", true);
cleanup = onCleanup(@() setappdataIfValid(fig, "smQueueResizing", false));

pos = get(fig, "Position");
target = pos;
target(3) = max(724, pos(3));
target(4) = max(600, pos(4));
if ~isequal(target, pos)
    set(fig, "Position", target);
end

h = guidata(fig);
if ~isstruct(h) || ~isfield(h, "schedule_panel")
    return;
end
w = target(3);
height = target(4);
margin = 10;
gap = 8;
topHeight = 72;
usableTopWidth = w - 2 * margin - 2 * gap;
saveWidth = round(0.40 * usableTopWidth);
pptWidth = round(0.35 * usableTopWidth);
notifyWidth = usableTopWidth - saveWidth - pptWidth;
topY = height - margin - topHeight;

set(h.save_panel, "Position", [margin topY saveWidth topHeight]);
set(h.ppt_panel, "Position", [margin + saveWidth + gap topY pptWidth topHeight]);
set(h.notify_panel, "Position", [margin + saveWidth + pptWidth + 2 * gap topY notifyWidth topHeight]);

runWidth = 50;
runLabelWidth = 42;
pathButtonWidth = 58;
set(h.savepath_pbh, "Position", [8 12 pathButtonWidth 25]);
set(h.run_eth, "Position", [saveWidth - runWidth - 8 12 runWidth 25]);
set(h.run_label, "Position", [saveWidth - runWidth - runLabelWidth - 11 13 runLabelWidth 20]);
pathX = 8 + pathButtonWidth + 7;
pathWidth = max(20, saveWidth - pathX - runWidth - runLabelWidth - 18);
set(h.datapath_sth, "Position", [pathX 14 pathWidth 19]);

set(h.pptauto_cbh, "Position", [8 12 126 24]);
set(h.pptfile_pbh, "Position", [137 12 54 25]);
set(h.pptfile_sth, "Position", [197 14 max(20, pptWidth - 205) 19]);
set(h.notify_label, "Position", [8 14 39 19]);
set(h.notify_account, "Position", [48 14 max(20, notifyWidth - 56) 19]);

scheduleY = margin;
scheduleHeight = max(100, topY - gap - scheduleY);
set(h.schedule_panel, "Position", [margin scheduleY w - 2 * margin scheduleHeight]);

scheduleWidth = w - 2 * margin;
innerMargin = 10;
columnGap = 8;
minimumCenterWidth = 120;
sideWidth = floor((scheduleWidth - 2 * innerMargin - minimumCenterWidth ...
    - 2 * columnGap) / 2);
centerWidth = scheduleWidth - 2 * innerMargin - 2 * columnGap - 2 * sideWidth;
contentY = 10;
safeHeight = 27;
safeY = scheduleHeight - 55;
if strcmp(get(h.safe_overlay, "Visible"), "on")
    contentHeight = safeY - 8 - contentY;
else
    contentHeight = scheduleHeight - 38;
end
leftX = innerMargin;
centerX = leftX + sideWidth + columnGap;
queueX = centerX + centerWidth + columnGap;

sourceGap = 8;
rawHeight = round(0.20 * (contentHeight - sourceGap));
scanHeight = contentHeight - sourceGap - rawHeight;
set(h.commands_panel, "Position", [leftX contentY sideWidth rawHeight]);
set(h.scans_panel, "Position", [leftX contentY + rawHeight + sourceGap sideWidth scanHeight]);
set(h.scans_lbh, "Position", [8 8 sideWidth - 16 scanHeight - 34]);
set(h.qtxt_eth, "Position", [8 8 sideWidth - 16 rawHeight - 34]);

buttonWidth = 96;
buttonHeight = 56;
buttonGap = 16;
buttonStackHeight = 3 * buttonHeight + 2 * buttonGap;
sourceLabelHeight = 24;
sourceLabelGap = 10;
buttonsBottom = min(contentY + round(0.58 * contentHeight), ...
    contentY + contentHeight - buttonStackHeight - sourceLabelGap - sourceLabelHeight);
buttonX = centerX + floor((centerWidth - buttonWidth) / 2);
set(h.insert_source_sth, "Position", ...
    [centerX buttonsBottom + buttonStackHeight + sourceLabelGap centerWidth sourceLabelHeight]);
set(h.insert_top_pbh, "Position", ...
    [buttonX buttonsBottom + 2 * (buttonHeight + buttonGap) buttonWidth buttonHeight]);
set(h.insert_after_pbh, "Position", ...
    [buttonX buttonsBottom + buttonHeight + buttonGap buttonWidth buttonHeight]);
set(h.insert_end_pbh, "Position", [buttonX buttonsBottom buttonWidth buttonHeight]);

set(h.queue_panel, "Position", [queueX contentY sideWidth contentHeight]);
statusY = contentHeight - 45;
controlHeight = 32;
controlY = statusY - controlHeight - 8;
set(h.status_sth, "Position", [8 statusY sideWidth - 16 20]);
minimumQueueControlGap = 15;
queueControlWidth = min(88, floor((sideWidth - 16 ...
    - 2 * minimumQueueControlGap) / 3));
set(h.run_pbh, "Position", [8 controlY queueControlWidth controlHeight]);
set(h.stopqueue_pbh, "Position", ...
    [floor((sideWidth - queueControlWidth) / 2) controlY queueControlWidth controlHeight]);
set(h.stopnow_pbh, "Position", ...
    [sideWidth - 8 - queueControlWidth controlY queueControlWidth controlHeight]);
set(h.moveup_pbh, "Position", [8 8 76 28]);
set(h.movedown_pbh, "Position", [92 8 82 28]);
set(h.removequeue_pbh, "Position", [182 8 76 28]);
set(h.queue_lbh, "Position", [8 44 sideWidth - 16 max(30, controlY - 52)]);
set(h.safe_overlay, "Position", [innerMargin safeY scheduleWidth - 2 * innerMargin safeHeight]);
uistack(h.safe_overlay, "top");
end

function setappdataIfValid(fig, name, value)
if isgraphics(fig)
    setappdata(fig, name, value);
end
end
