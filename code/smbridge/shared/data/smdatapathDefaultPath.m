function pathStr = smdatapathDefaultPath()
%SMDATAPATHDEFAULTPATH Compute the default data directory.
%
%   Returns `<pwd>/data`. Caller is responsible for creating the directory
%   if desired.

    baseDir = pwd;
    pathStr = fullfile(baseDir, 'data');
end


