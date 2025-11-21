function smrunUpdateGlobalState(source, runValue)
%SMRUNUPDATEGLOBALSTATE Persist run-number changes and notify GUIs.
%
%   SOURCE identifies which component initiated the change (e.g. 'small',
%   'main'). RUNVALUE may be empty/NaN to disable run numbering.

    global smrunConfig

    if nargin < 1 || isempty(source)
        source = '';
    end

    smrunEnsureGlobals();

    if nargin < 2
        runValue = smrunConfig.run;
    end

    if isempty(runValue) || all(isnan(runValue(:)))
        newRun = NaN;
    else
        newRun = normalizeRunValue(runValue);
    end

    if runsAreEqual(smrunConfig.run, newRun)
        smrunConfig.lastUpdatedBy = source;
        smrunApplyStateToRegisteredGuis(source);
        return;
    end

    smrunConfig.run = newRun;
    smrunConfig.lastUpdatedBy = source;

    smrunSyncSmauxFromGlobal();
    smrunApplyStateToRegisteredGuis(source);
end


function tf = runsAreEqual(a, b)
    tf = (isnan(a) && isnan(b)) || (~isnan(a) && ~isnan(b) && a == b);
end


function value = normalizeRunValue(value)
    value = double(value);
    value = round(value);
    value = mod(value, 1000);
    value(value < 0) = value(value < 0) + 1000;
end


