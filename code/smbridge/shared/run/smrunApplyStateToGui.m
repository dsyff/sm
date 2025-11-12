function smrunApplyStateToGui(guiName)
%SMRUNAPPLYSTATETOGUI Update GUI controls to show current run value.

    global smrunGui

    smrunEnsureGlobals();

    if ~isfield(smrunGui, guiName)
        return;
    end

    handlesStruct = smrunGui.(guiName);
    if ~isstruct(handlesStruct) || isempty(fieldnames(handlesStruct))
        return;
    end

    runValue = smrunGetState();

    if isfield(handlesStruct, 'edit') && ishandle(handlesStruct.edit)
        if isnan(runValue)
            set(handlesStruct.edit, 'String', '');
        else
            set(handlesStruct.edit, 'String', sprintf('%03u', uint16(runValue)));
        end
    end

    if isfield(handlesStruct, 'tooltipHandle') && ishandle(handlesStruct.tooltipHandle)
        if isnan(runValue)
            set(handlesStruct.tooltipHandle, 'TooltipString', '');
        else
            set(handlesStruct.tooltipHandle, 'TooltipString', sprintf('%03u', uint16(runValue)));
        end
    end

    smrunSyncSmauxFromGlobal();
end


