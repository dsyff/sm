function smrunEnsureGlobals()
%SMRUNENSUREGLOBALS Initialize shared run-number state bookkeeping.
%
%   Maintains a shared struct so both GUIs and runtime helpers can agree on
%   the next run number to use.

    global smrunConfig smrunGui smaux

    if isempty(smrunConfig) || ~isstruct(smrunConfig)
        initialRun = extractInitialRun();
        smrunConfig = struct('run', initialRun, 'lastUpdatedBy', '');
    else
        if ~isfield(smrunConfig, 'run')
            smrunConfig.run = extractInitialRun();
        end
        if ~isfield(smrunConfig, 'lastUpdatedBy')
            smrunConfig.lastUpdatedBy = '';
        end
        smrunConfig.run = normalizeRunValue(smrunConfig.run);
    end

    if isempty(smrunGui) || ~isstruct(smrunGui)
        smrunGui = struct('small', struct(), 'main', struct());
    else
        if ~isfield(smrunGui, 'small')
            smrunGui.small = struct();
        end
        if ~isfield(smrunGui, 'main')
            smrunGui.main = struct();
        end
    end

    if ~isstruct(smaux)
        smaux = struct();
    end

    smrunSyncSmauxFromGlobal();
end


function value = extractInitialRun()
    global smaux
    if isstruct(smaux) && isfield(smaux, 'run') && ~isempty(smaux.run)
        value = normalizeRunValue(smaux.run);
    else
        value = 1;
    end
end


function value = normalizeRunValue(value)
    if isempty(value) || all(isnan(value(:)))
        value = NaN;
        return;
    end
    value = double(value);
    value = round(value);
    value = mod(value, 1000);
    value(value < 0) = value(value < 0) + 1000;
end


