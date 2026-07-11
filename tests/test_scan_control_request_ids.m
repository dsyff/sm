rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(rootDir));

origVisible = get(0, "DefaultFigureVisible");
testDir = tempname;
cleanupObj = onCleanup(@() cleanupTest(origVisible, testDir));
set(0, "DefaultFigureVisible", "off");
mkdir(testDir);

recipe = instrumentRackRecipe();
recipe.addInstrument("handle_sweep", "instrument_counter", "Counter_sweep", "Counter_sweep");
recipe.addInstrument("handle_signal", "instrument_counter", "Counter_signal", "Counter_signal");
recipe.addStatement("Counter_sweep", "handle_sweep.requireSetCheck = false;");
recipe.addStatement("Counter_signal", "handle_signal.requireSetCheck = false;");
recipe.addChannel("Counter_sweep", "count", "sweep");
recipe.addChannel("Counter_signal", "count", "signal");
engine = measurementEngine(recipe);

send(engine.scanControlToEngine, struct("type", "stop", "requestId", "stale-run"));
send(engine.scanControlToEngine, struct("type", "stop"));

scan = struct();
scan.name = "test_scan_control_request_ids";
scan.loops(1).npoints = 1;
scan.loops(1).rng = [0 0];
scan.loops(1).getchan = {"signal"};
scan.loops(1).setchan = {"sweep"};
scan.loops(1).setchanranges = {[0 0]};
scan.loops(1).waittime = 0;
scan.loops(1).startwait = 0;
scan.saveloop = 1;
scan.disp = struct("loop", {}, "channel", {}, "dim", {}, "name", {});

[~, metadata] = engine.run(scan, string(fullfile(testDir, "safe_request_id.mat")), "safe");
assert(metadata.isComplete, "Stale or malformed scan-control message affected the current safe scan.");

disp("PASS: safe scan ignores stale and malformed scan-control messages.");

function cleanupTest(origVisible, testDir)
    try
        close all force;
    catch
    end
    try
        pool = gcp("nocreate");
        if ~isempty(pool)
            delete(pool);
        end
    catch
    end
    try
        set(0, "DefaultFigureVisible", origVisible);
    catch
    end
    try
        if exist(testDir, "dir")
            rmdir(testDir, "s");
        end
    catch
    end
end
