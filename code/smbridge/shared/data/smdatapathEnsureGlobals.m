function smdatapathEnsureGlobals()
%SMDATAPATHENSUREGLOBALS Prepare shared data-path state structures.

    global smdatapathConfig smdatapathGui smaux

    if isstruct(smaux) && isfield(smaux, 'datadir') && ~isempty(smaux.datadir)
        defaultPath = char(smaux.datadir);
    else
        defaultPath = smdatapathDefaultPath();
        if isstruct(smaux)
            smaux.datadir = defaultPath;
        end
    end

    if isempty(smdatapathConfig) || ~isstruct(smdatapathConfig)
        smdatapathConfig = struct('path', defaultPath, 'lastUpdatedBy', '');
    else
        if ~isfield(smdatapathConfig, 'path')
            smdatapathConfig.path = defaultPath;
        end
        if ~isfield(smdatapathConfig, 'lastUpdatedBy')
            smdatapathConfig.lastUpdatedBy = '';
        end
    end

    if isempty(smdatapathGui) || ~isstruct(smdatapathGui)
        smdatapathGui = struct('small', struct(), 'main', struct());
    else
        if ~isfield(smdatapathGui, 'small')
            smdatapathGui.small = struct();
        end
        if ~isfield(smdatapathGui, 'main')
            smdatapathGui.main = struct();
        end
    end

    if ~isstruct(smaux)
        smaux = struct();
        smaux.datadir = defaultPath;
    end

    smdatapathSyncSmauxFromGlobal();
end


