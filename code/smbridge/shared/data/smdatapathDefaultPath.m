function pathStr = smdatapathDefaultPath()
%SMDATAPATHDEFAULTPATH Compute the default data directory.
%
%   Returns `<experimentRootPath>/data` when available, otherwise `<pwd>/data`.
%   Caller is responsible for creating the directory if desired.

    global bridge
    baseDir = pwd;
    if exist("bridge", "var") && ~isempty(bridge) && isobject(bridge) && isprop(bridge, "experimentRootPath")
        rootCandidate = string(bridge.experimentRootPath);
        if strlength(rootCandidate) > 0
            baseDir = char(rootCandidate);
        end
    end
    pathStr = fullfile(baseDir, "data");
end


