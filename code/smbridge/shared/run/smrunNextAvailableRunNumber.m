function runValue = smrunNextAvailableRunNumber(dataDir, candidate)
%SMRUNNEXTAVAILABLERUNNUMBER Find the next unused run number.
%
%   Returns the first run number >= candidate (with wrap-around) whose
%   prefix does not collide with existing files in DATADIR.

    if nargin < 2 || isnan(candidate)
        error('smrun:InvalidCandidate', 'Candidate run number must be provided.');
    end

    if isempty(dataDir)
        runValue = mod(round(double(candidate)), 1000);
        return;
    end

    candidate = mod(round(double(candidate)), 1000);

    for offset = 0:999
        testValue = mod(candidate + offset, 1000);
        if ~smrunHasCollision(dataDir, testValue)
            runValue = testValue;
            return;
        end
    end

    error('smrun:RunNumberExhausted', ...
        'All run numbers (000-999) appear to be in use for directory %s.', dataDir);
end


