function active = smbridgeQueueRunnerActive()
%SMBRIDGEQUEUERUNNERACTIVE Report an existing non-idle queue runner.
%#ok<*GVMIS>

global smaux
active = isstruct(smaux) && isfield(smaux, "queueState") ...
    && isa(smaux.queueState, "smQueueState") && isvalid(smaux.queueState) ...
    && smaux.queueState.snapshot().queuePhase ~= "idle";
end
