rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(rootDir));

origVisible = get(0, "DefaultFigureVisible");
testDir = tempname;
cleanupObj = onCleanup(@() cleanupTest(origVisible, testDir));
set(0, "DefaultFigureVisible", "off");
mkdir(testDir);

rack = instrumentRack(true);

instSweep = instrument_counter("Counter_sweep");
rack.addInstrument(instSweep, "Counter_sweep");
rack.addChannel("Counter_sweep", "count", "sweep");

instSignal = instrument_counter("Counter_signal");
rack.addInstrument(instSignal, "Counter_signal");
rack.addChannel("Counter_signal", "count", "signal");

instSetConst = instrument_counter("Counter_setconst");
rack.addInstrument(instSetConst, "Counter_setconst");
rack.addChannel("Counter_setconst", "count", "sconst");

instGetConst = instrument_counter("Counter_getconst");
rack.addInstrument(instGetConst, "Counter_getconst");
rack.addChannel("Counter_getconst", "count", "gconst");

rack.rackSet(["signal"; "gconst"], [11; 42]);
engine = measurementEngine.fromRack(rack);

scan = struct();
scan.name = "test_scan_get_constants_saved";
scan.loops(1).npoints = 1;
scan.loops(1).rng = [0 0];
scan.loops(1).getchan = {"signal"};
scan.loops(1).setchan = {"sweep"};
scan.loops(1).setchanranges = {[0 0]};
scan.loops(1).waittime = 0;
scan.loops(1).startwait = 0;
scan.saveloop = 1;
scan.disp = struct("loop", {}, "channel", {}, "dim", {}, "name", {});
scan.consts = [ ...
    struct("setchan", "sconst", "val", 7, "set", 1), ...
    struct("setchan", "gconst", "val", -1, "set", 0) ...
];

filename = fullfile(testDir, "const_scan.mat");
engine.run(scan, string(filename), "safe");

assertSavedConsts(load(filename, "scan").scan, filename);
[scanPath, scanName] = fileparts(filename);
assertSavedConsts(load(fullfile(scanPath, scanName + "_scan.mat"), "scan").scan, scanName + "_scan.mat");

disp("PASS: saved scan consts are refreshed once at run start without stale get-constant values.");

function assertSavedConsts(scanStruct, sourceLabel)
    assert(numel(scanStruct.consts) == 2, "Expected 2 const entries in %s.", string(sourceLabel));
    assert(abs(scanStruct.consts(1).val - 7) < 1E-9, ...
        "Expected set constant value 7 in %s, got %.15g.", string(sourceLabel), scanStruct.consts(1).val);
    assert(abs(scanStruct.consts(2).val - 42) < 1E-9, ...
        "Expected refreshed get constant value 42 in %s, got %.15g.", string(sourceLabel), scanStruct.consts(2).val);
end

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
