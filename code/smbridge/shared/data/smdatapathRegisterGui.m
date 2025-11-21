function smdatapathRegisterGui(guiName, handlesStruct)
%SMDATAPATHREGISTERGUI Register GUI handles to sync data path display.

    global smdatapathGui

    if nargin < 2
        return;
    end

    smdatapathEnsureGlobals();

    smdatapathGui.(guiName) = handlesStruct;
    smdatapathApplyStateToGui(guiName);
end


