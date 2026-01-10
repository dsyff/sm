warning("sminit:Moved", "sminit moved to code/sminit.m; calling it from smbridge is deprecated.");

st = dbstack("-completenames");
if isempty(st) || ~isfield(st, "file") || strlength(string(st(1).file)) == 0
    error("sminit:CannotDetermineLocation", "Unable to determine sminit location (dbstack empty).");
end

smbridgeDir = fileparts(string(st(1).file));
codeDir = fileparts(smbridgeDir);

run(fullfile(codeDir, "sminit.m"));

