global instrumentRackGlobal smscan smaux smdata bridge tareData; %#ok<NUSED>

% Ensure sm-dev code folders on path (avoid instruments/private)
st = dbstack("-completenames");
if isempty(st) || ~isfield(st, "file") || strlength(string(st(1).file)) == 0
    error("sminit:CannotDetermineLocation", "Unable to determine sminit location (dbstack empty).");
end

codeDir = fileparts(string(st(1).file));
addpath(codeDir);

codeEntries = dir(codeDir);
for i = 1:numel(codeEntries)
    if ~codeEntries(i).isdir
        continue;
    end

    name = string(codeEntries(i).name);
    if name == "." || name == ".."
        continue;
    end

    folderPath = fullfile(codeDir, name);
    if name == "instruments"
        % Only top-level instruments folder to avoid adding private subfolders
        addpath(folderPath);
    else
        addpath(genpath(folderPath));
    end
end

% Check MATLAB version (R2024a or newer required)
if isMATLABReleaseOlderThan("R2024a")
    error("sminit: MATLAB version is too old. SM1.5 requires MATLAB R2024a or newer. Current version: " + version("-release"));
end

close all;
selection = questdlg("Has Windows Update been postponed? Updates can interrupt long measurements.", ...
    "Postpone Windows Update", "Yes", "Not Yet", "Not Yet");
if selection ~= "Yes"
    error("sminit aborted: postpone Windows Update before starting measurements.");
end
% Clean up existing instruments to release serial ports
if exist("instrumentRackGlobal", "var") && ~isempty(instrumentRackGlobal)
    try
        delete(instrumentRackGlobal);
    catch ME
        fprintf("sminit deleteInstrumentRackGlobalFailed: %s\n", ME.message);
    end
    clear instrumentRackGlobal;
end

delete(visadevfind);
delete(serialportfind);
clear;
%clear all;
global instrumentRackGlobal smscan smaux smdata bridge tareData;
%#ok<GVMIS,NUSED>

