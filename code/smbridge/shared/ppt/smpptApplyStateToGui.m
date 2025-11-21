function smpptApplyStateToGui(guiName)
%SMPPTAPPLYSTATETOGUI Update a GUI's widgets to match PPT settings.

    global smpptGui

    smpptEnsureGlobals();

    if ~isfield(smpptGui, guiName)
        return;
    end

    handlesStruct = smpptGui.(guiName);
    if ~isstruct(handlesStruct) || isempty(fieldnames(handlesStruct))
        return;
    end

    [enabled, file] = smpptGetState();

    if isfield(handlesStruct, 'checkbox') && ishandle(handlesStruct.checkbox)
        set(handlesStruct.checkbox, 'Value', double(enabled));
    end

    if isfield(handlesStruct, 'fileLabel') && ishandle(handlesStruct.fileLabel)
        if isempty(file)
            displayName = '';
        else
            [~, name, ext] = fileparts(file);
            displayName = [name ext];
        end
        set(handlesStruct.fileLabel, 'String', displayName);
        set(handlesStruct.fileLabel, 'TooltipString', file);
    end
end


