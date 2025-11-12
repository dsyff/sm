function smdatapathApplyStateToGui(guiName)
%SMDATAPATHAPPLYSTATETOGUI Update GUI components with shared data path.

    global smdatapathGui

    smdatapathEnsureGlobals();

    if ~isfield(smdatapathGui, guiName)
        return;
    end

    handlesStruct = smdatapathGui.(guiName);
    if ~isstruct(handlesStruct) || isempty(fieldnames(handlesStruct))
        return;
    end

    pathStr = smdatapathGetState();
    if isempty(pathStr)
        pathStr = smdatapathDefaultPath();
        smdatapathUpdateGlobalState(guiName, pathStr);
    end

    displayLimit = 40;
    if isfield(handlesStruct, 'displayLimit') && ~isempty(handlesStruct.displayLimit)
        displayLimit = handlesStruct.displayLimit;
    end

    [displayString, tooltipString] = smdatapathFormatForDisplay(pathStr, displayLimit);

    if isfield(handlesStruct, 'label') && ishandle(handlesStruct.label)
        set(handlesStruct.label, 'String', displayString);
    end

    tooltipHandle = [];
    if isfield(handlesStruct, 'tooltipHandle') && ishandle(handlesStruct.tooltipHandle)
        tooltipHandle = handlesStruct.tooltipHandle;
    elseif isfield(handlesStruct, 'label') && ishandle(handlesStruct.label)
        tooltipHandle = handlesStruct.label;
    end
    if ~isempty(tooltipHandle)
        set(tooltipHandle, 'TooltipString', tooltipString);
    end
end


