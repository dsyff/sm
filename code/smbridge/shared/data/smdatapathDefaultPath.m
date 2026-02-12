function pathStr = smdatapathDefaultPath()
%SMDATAPATHDEFAULTPATH Compute the default data directory.
%
%   Returns `<experimentRootPath>/data` when available, otherwise `<pwd>/data`.
%   Caller is responsible for creating the directory if desired.

    baseDir = pwd;
    rootCandidate = experimentContext.getExperimentRootPath();
    if strlength(rootCandidate) > 0
        baseDir = char(rootCandidate);
    end
    pathStr = fullfile(baseDir, "data");
end


