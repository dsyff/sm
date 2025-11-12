function smpptEnsureGlobals()
%SMPPTENSUREGLOBALS Initialize shared PowerPoint state structures.
%
%   Keeps the shared PowerPoint configuration and GUI handle registries
%   ready for use across the bridge GUIs.

    global smpptConfig smpptGui smaux

    if isempty(smpptConfig) || ~isstruct(smpptConfig)
        smpptConfig = struct('enabled', true, 'file', '', 'lastUpdatedBy', '');
    else
        if ~isfield(smpptConfig, 'enabled')
            smpptConfig.enabled = true;
        end
        if ~isfield(smpptConfig, 'file')
            smpptConfig.file = '';
        end
        if ~isfield(smpptConfig, 'lastUpdatedBy')
            smpptConfig.lastUpdatedBy = '';
        end
    end

    if isempty(smpptGui) || ~isstruct(smpptGui)
        smpptGui = struct('small', struct(), 'main', struct());
    else
        if ~isfield(smpptGui, 'small')
            smpptGui.small = struct();
        end
        if ~isfield(smpptGui, 'main')
            smpptGui.main = struct();
        end
    end

    if ~isstruct(smaux)
        smaux = struct();
    end

    smpptSyncSmauxFromGlobal();
end


