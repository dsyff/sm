function test_instrumentRack_ramping_state
projectRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(fullfile(projectRoot, "code")));

testDirectRackSetWriteUsesCommandedOrigin();
testHysteresisVirtualWriteUsesCommandedOrigin();
testVirtualNEBatchWriteUsesNestedCommandedOrigin();
testFirstSetReadFailureUsesRackRetry();

fprintf("test_instrumentRack_ramping_state passed.\n");
end

function testDirectRackSetWriteUsesCommandedOrigin()
rack = instrumentRack(true);
cleanupObj = onCleanup(@() delete(rack));

trace = instrument_rampTrace("trace_direct");
trace.requireSetCheck = false;
rack.addInstrument(trace, "trace");
rack.addChannel("trace", "value", "V", 1000, 0.5, -200, 200);

rack.rackSet("V", 0);
trace.clearHistory();
rack.rackSetWrite("V", 100);
trace.clearHistory();
rack.rackSetWrite("V", 101);

assert(min(trace.writeHistory) > 99, ...
    "Direct rackSetWrite ramp restarted from stale verified state.");
end

function testHysteresisVirtualWriteUsesCommandedOrigin()
rack = instrumentRack(true);
cleanupObj = onCleanup(@() delete(rack));

trace = instrument_rampTrace("trace_hysteresis");
trace.requireSetCheck = false;
rack.addInstrument(trace, "trace");
rack.addChannel("trace", "value", "V_tg", 1000, 0.5, -200, 200);
rack.rackSet("V_tg", 0);

virtualHys = virtualInstrument_hysteresis("virtual_hys", rack, ...
    setChannelName = "V_tg", min = 0, max = 100);
virtualHys.requireSetCheck = false;
rack.addInstrument(virtualHys, "virtual_hys");
rack.addChannel("virtual_hys", "hysteresis", "hys_V_tg", [], [], 0, 1);

trace.clearHistory();
rack.rackSetWrite("hys_V_tg", 0.5);
trace.clearHistory();
rack.rackSetWrite("hys_V_tg", 0.495);

assert(min(trace.writeHistory) > 90, ...
    "Virtual hysteresis ramp restarted from stale V_tg verified state.");
end

function testVirtualNEBatchWriteUsesNestedCommandedOrigin()
rack = instrumentRack(true);
cleanupObj = onCleanup(@() delete(rack));

traceTg = instrument_rampTrace("trace_tg");
traceBg = instrument_rampTrace("trace_bg");
traceTg.requireSetCheck = false;
traceBg.requireSetCheck = false;
rack.addInstrument(traceTg, "trace_tg");
rack.addInstrument(traceBg, "trace_bg");
rack.addChannel("trace_tg", "value", "V_tg", 1000, 0.5, -300, 300);
rack.addChannel("trace_bg", "value", "V_bg", 1000, 0.5, -300, 300);
rack.rackSet(["V_tg"; "V_bg"], [0; 0]);

virtualNE = virtualInstrument_nE("virtual_nE", rack, ...
    vTgChannelName = "V_tg", ...
    vBgChannelName = "V_bg", ...
    vTgLimits = [-300, 300], ...
    vBgLimits = [-300, 300], ...
    vTg_n0E0 = 0, ...
    vBg_n0E0 = 0, ...
    vTg_n0ENot0 = 1, ...
    vBg_n0ENot0 = -1);
rack.addInstrument(virtualNE, "virtual_nE");
rack.addChannel("virtual_nE", "n", "n", [], [], 0, 1);
rack.addChannel("virtual_nE", "E", "E", [], [], 0, 1);
rack.addChannel("virtual_nE", "nE_within_bounds", "nE_within_bounds");
rack.addChannel("virtual_nE", "nFast0EFast1", "nFast0EFast1", [], [], 0, 1);

traceTg.clearHistory();
rack.rackSetWrite(["n"; "E"], [2/3; 2/3]);

history = traceTg.writeHistory;
firstTargetIndex = find(history >= 99, 1, "first");
assert(~isempty(firstTargetIndex), "Expected first n/E internal V_tg target near 100.");
assert(all(history(firstTargetIndex:end) > 90), ...
    "virtualInstrument_nE second internal V_tg ramp restarted from stale verified state.");
end

function testFirstSetReadFailureUsesRackRetry()
rack = instrumentRack(true);
cleanupObj = onCleanup(@() delete(rack));

trace = instrument_rampTrace("trace_transient_read");
trace.requireSetCheck = false;
rack.tryTimes = 2;
rack.tryInterval = seconds(0);
rack.addInstrument(trace, "trace");
rack.addChannel("trace", "value", "V", 1000, 0.5, -200, 200);
trace.failNextReads = 1;

rack.rackSetWrite("V", 100);

assert(trace.readFailureCount == 1, "Expected exactly one transient read failure.");
assert(trace.writeHistory(end) == 100, "Expected retry to complete the first set.");
end
