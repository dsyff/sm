function smrunRegisterGui(guiName, handlesStruct)
%SMRUNREGISTERGUI Register GUI widgets that reflect run-number state.

    global smrunGui

    if nargin < 2 || isempty(handlesStruct)
        return;
    end

    smrunEnsureGlobals();

    smrunGui.(guiName) = handlesStruct;
    smrunApplyStateToGui(guiName);
end


