function smbridgeUpdateEditRackMenuState(isRunningOverride)
    global smaux engine

    if nargin < 1 || isempty(isRunningOverride)
        isRunning = false;
        if exist("engine", "var") && ~isempty(engine) && isa(engine, "measurementEngine")
            isRunning = logical(engine.isScanInProgress);
        end
    else
        isRunning = logical(isRunningOverride);
    end

    reason = "Unavailable while a scan is running.";
    menuHandles = gobjects(0, 1);
    if isstruct(smaux)
        if isfield(smaux, "sm") && isstruct(smaux.sm) && isfield(smaux.sm, "editrack") && ishandle(smaux.sm.editrack)
            menuHandles(end+1, 1) = smaux.sm.editrack;
        end
        if isfield(smaux, "smgui") && isstruct(smaux.smgui) && isfield(smaux.smgui, "EditRack") && ishandle(smaux.smgui.EditRack)
            menuHandles(end+1, 1) = smaux.smgui.EditRack;
        end
    end

    for i = 1:numel(menuHandles)
        menuHandle = menuHandles(i);
        if ~ishandle(menuHandle)
            continue;
        end

        baseLabel = string(getappdata(menuHandle, "smEditRackBaseLabel"));
        if ~isscalar(baseLabel) || ismissing(baseLabel) || strlength(strtrim(baseLabel)) == 0
            baseLabel = string(get(menuHandle, "Label"));
            baseLabel = erase(baseLabel, " (scan active)");
            if ~isscalar(baseLabel) || ismissing(baseLabel) || strlength(strtrim(baseLabel)) == 0
                continue;
            end
            setappdata(menuHandle, "smEditRackBaseLabel", baseLabel);
        end

        if isRunning
            set(menuHandle, "Enable", "off");
            tooltipApplied = true;
            try
                set(menuHandle, "TooltipString", reason);
            catch
                tooltipApplied = false;
            end
            if tooltipApplied
                set(menuHandle, "Label", char(baseLabel));
            else
                set(menuHandle, "Label", char(baseLabel + " (scan active)"));
            end
        else
            set(menuHandle, "Enable", "on");
            try
                set(menuHandle, "TooltipString", "");
            catch
            end
            set(menuHandle, "Label", char(baseLabel));
        end
    end
end
