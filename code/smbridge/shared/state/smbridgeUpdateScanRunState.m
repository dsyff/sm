function unavailable = smbridgeUpdateScanRunState()
%SMBRIDGEUPDATESCANRUNSTATE Guard the scan editor Run action.
%#ok<*GVMIS>

global engine smaux
engineActive = ~isempty(engine) && isa(engine, "measurementEngine") && isvalid(engine) ...
    && (engine.isScanInProgress || engine.activeRunPhase ~= "idle");
unavailable = engineActive || smbridgeQueueRunnerActive();

if isstruct(smaux) && isfield(smaux, "smgui") && isstruct(smaux.smgui) ...
        && isfield(smaux.smgui, "smrun_pbh") && ishandle(smaux.smgui.smrun_pbh)
    set(smaux.smgui.smrun_pbh, "Enable", onOff(~unavailable));
end
end

function value = onOff(condition)
if condition
    value = "on";
else
    value = "off";
end
end
