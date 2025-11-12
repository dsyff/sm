function smpptRegisterGui(guiName, handlesStruct)
%SMPPTREGISTERGUI Register GUI handles to receive PPT state updates.

    global smpptGui

    if nargin < 2
        return;
    end

    smpptEnsureGlobals();

    smpptGui.(guiName) = handlesStruct;
    smpptApplyStateToGui(guiName);
end


