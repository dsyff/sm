function smpptSyncSmauxFromGlobal()
%SMPPTSYNCSMAUXFROMGLOBAL Mirror PPT state into smaux for legacy consumers.

    global smpptConfig smaux

    if isempty(smpptConfig) || ~isstruct(smpptConfig)
        return;
    end

    if ~isstruct(smaux)
        smaux = struct();
    end

    smaux.pptsavefile = smpptConfig.file;
    smaux.pptenabled = smpptConfig.enabled;
end


