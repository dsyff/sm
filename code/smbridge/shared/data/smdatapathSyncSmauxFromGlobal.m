function smdatapathSyncSmauxFromGlobal()
%SMDATAPATHSYNCSMAUXFROMGLOBAL Mirror shared data-path into smaux.

    global smdatapathConfig smaux

    if isempty(smdatapathConfig) || ~isstruct(smdatapathConfig)
        return;
    end

    if ~isstruct(smaux)
        smaux = struct();
    end

    smaux.datadir = smdatapathConfig.path;
end


