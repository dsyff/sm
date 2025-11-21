function smbridgeAddSharedPaths()
%SMBRIDGEADDSHAREDPATHS Ensure shared helper folders are on the MATLAB path.
%
%   Idempotent helper used by both GUIs and runtime functions so that shared
%   utilities under `shared/ppt` and `shared/data` remain reachable.

    persistent added;
    if ~isempty(added) && added
        return;
    end

    baseDir = fileparts(mfilename('fullpath'));
    sharedDirs = {fullfile(baseDir, 'shared', 'ppt'), ...
                  fullfile(baseDir, 'shared', 'data'), ...
                  fullfile(baseDir, 'shared', 'run')};

    for k = 1:numel(sharedDirs)
        dirPath = sharedDirs{k};
        if exist(dirPath, 'dir') && isempty(strfind(path, dirPath))
            addpath(dirPath);
        end
    end

    added = true;
end


