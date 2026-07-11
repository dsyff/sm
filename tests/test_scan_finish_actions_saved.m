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

instFinishSet = instrument_counter("Counter_finish_set");
rack.addInstrument(instFinishSet, "Counter_finish_set");
rack.addChannel("Counter_finish_set", "count", "gate");

instFinishGet = instrument_counter("Counter_finish_get");
rack.addInstrument(instFinishGet, "Counter_finish_get");
rack.addChannel("Counter_finish_get", "count", "leakage");

rack.rackSet(["signal"; "gate"; "leakage"], [11; 5; 42]);
engine = measurementEngine.fromRack(rack);

scan = struct();
scan.name = "test_scan_finish_actions_saved";
scan.loops(1).npoints = 1;
scan.loops(1).rng = [0 0];
scan.loops(1).getchan = {"signal"};
scan.loops(1).setchan = {"sweep"};
scan.loops(1).setchanranges = {[0 0]};
scan.loops(1).waittime = 0;
scan.loops(1).startwait = 0;
scan.saveloop = 1;
scan.disp = struct("loop", {}, "channel", {}, "dim", {}, "name", {});
scan.finish = [ ...
    struct("setchan", "gate", "val", 0, "set", 1), ...
    struct("setchan", "leakage", "val", -1, "set", 0) ...
];

filename = fullfile(testDir, "finish_scan.mat");
engine.run(scan, string(filename), "safe");

assert(abs(rack.rackGet("gate") - 0) < 1E-9, "Finish set row did not set gate to zero.");
assertSavedFinish(load(filename, "scan").scan, filename);
[scanPath, scanName] = fileparts(filename);
assertSavedFinish(load(fullfile(scanPath, scanName + "_scan.mat"), "scan").scan, scanName + "_scan.mat");

rack.tryTimes = 1;
rack.tryInterval = seconds(0);
instError = instrument_error("Error_get");
rack.addInstrument(instError, "Error_get");
rack.addChannel("Error_get", "error_channel", "error_get");
rack.rackSet("gate", 5);
errorScan = scan;
errorScan.name = "test_scan_finish_actions_on_error";
errorScan.loops(1).getchan = {"error_get"};
errorScan.finish = struct("setchan", "gate", "val", 0, "set", 1);
try
    engine.run(errorScan, string(fullfile(testDir, "finish_error_scan.mat")), "safe");
    error("test_scan_finish_actions_saved:ExpectedScanError", "Expected the scan get to fail.");
catch ME
    assert(ME.identifier == "instrument_error:GetWriteError", ...
        "Expected original scan error after finish actions, received %s.", ME.identifier);
end
assert(abs(rack.rackGet("gate")) < 1E-9, "Finish set row did not run after scan error.");

disp("PASS: finish actions run before final save and before scan errors are rethrown.");

function assertSavedFinish(scanStruct, sourceLabel)
    assert(isfield(scanStruct, "finish"), "Missing finish field in %s.", string(sourceLabel));
    assert(numel(scanStruct.finish) == 2, "Expected 2 finish entries in %s.", string(sourceLabel));
    assert(abs(scanStruct.finish(1).val - 0) < 1E-9, ...
        "Expected finish set value 0 in %s, got %.15g.", string(sourceLabel), scanStruct.finish(1).val);
    assert(logical(scanStruct.finish(1).set), "Expected first finish entry to be a set row in %s.", string(sourceLabel));
    assert(abs(scanStruct.finish(2).val - 42) < 1E-9, ...
        "Expected refreshed finish read value 42 in %s, got %.15g.", string(sourceLabel), scanStruct.finish(2).val);
    assert(~logical(scanStruct.finish(2).set), "Expected second finish entry to be a read row in %s.", string(sourceLabel));
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
