rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(rootDir));

global engine bridge smaux smscan %#ok<GVMIS>
origVisible = get(0, "DefaultFigureVisible");
cleanupObj = onCleanup(@() cleanupGuiSmoke(origVisible));
set(0, "DefaultFigureVisible", "off");

rack = instrumentRack(true);
instGate = instrument_counter("Counter_gate");
rack.addInstrument(instGate, "Counter_gate");
rack.addChannel("Counter_gate", "count", "gate");
instSignal = instrument_counter("Counter_signal");
rack.addInstrument(instSignal, "Counter_signal");
rack.addChannel("Counter_signal", "count", "signal");

engine = measurementEngine.fromRack(rack);
bridge = smguiBridge(engine);
bridge.initializeSmdata();
smscan = [];
smaux = [];

smgui_small;
drawnow;

assert(isfield(smaux.smgui, "scan_finish_ph") && isgraphics(smaux.smgui.scan_finish_ph), ...
    "Missing finish panel.");
assert(strcmp(string(get(smaux.smgui.scan_finish_ph, "Title")), ...
    "When finished or canceled (check to set and uncheck to record)"), ...
    "Unexpected finish panel title.");
assert(~isempty(smaux.smgui.finish_pmh) && isgraphics(smaux.smgui.finish_pmh(1)), ...
    "Missing finish row popup.");

disp("PASS: finish action GUI panel smoke test.");

function cleanupGuiSmoke(origVisible)
    global engine smaux %#ok<GVMIS>
    try
        if isstruct(smaux) && isfield(smaux, "smgui") && isfield(smaux.smgui, "figure1") && isgraphics(smaux.smgui.figure1)
            delete(smaux.smgui.figure1);
        end
    catch
    end
    try
        if ~isempty(engine)
            delete(engine);
        end
    catch
    end
    try
        close all force;
    catch
    end
    try
        set(0, "DefaultFigureVisible", origVisible);
    catch
    end
end
