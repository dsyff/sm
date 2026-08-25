function applied = smrunUpdateGlobalState(source, runValue, expectedRevision)
%SMRUNUPDATEGLOBALSTATE Persist run-number changes and notify GUIs.
%
%   SOURCE identifies which component initiated the change (e.g. 'small',
%   'main'). RUNVALUE may be empty/NaN to disable run numbering. When
%   EXPECTEDREVISION is supplied, the update is applied only if no newer
%   shared-state edit has occurred.

    global smrunConfig

    if nargin < 1 || isempty(source)
        source = '';
    end

    smrunEnsureGlobals();
    applied = false;

    if nargin >= 3
        if ~isnumeric(expectedRevision) || ~isscalar(expectedRevision) || ...
                ~isfinite(expectedRevision) || expectedRevision < 0 || ...
                expectedRevision ~= floor(expectedRevision)
            error("smrun:InvalidRevision", "Expected run-state revision must be a nonnegative integer scalar.");
        end
        if double(expectedRevision) ~= smrunConfig.revision
            return;
        end
    end

    if nargin < 2
        runValue = smrunConfig.run;
    end

    if isempty(runValue) || all(isnan(runValue(:)))
        newRun = NaN;
    else
        newRun = normalizeRunValue(runValue);
    end

    if ~runsAreEqual(smrunConfig.run, newRun)
        smrunConfig.run = newRun;
        smrunSyncSmauxFromGlobal();
    end

    smrunConfig.lastUpdatedBy = source;
    smrunConfig.revision = smrunConfig.revision + 1;
    smrunApplyStateToRegisteredGuis(source);
    applied = true;
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

