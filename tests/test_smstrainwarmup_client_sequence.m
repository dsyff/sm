rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(rootDir));
clear cleanupObj

global engine %#ok<GVMIS>
rack = instrumentRack(true);
channels = ["activeControl"; "V_str_i"; "V_str_o"];
for channelIdx = 1:numel(channels)
    instrumentName = "Counter_" + string(channelIdx);
    inst = instrument_counter(instrumentName);
    rack.addInstrument(inst, instrumentName);
    rack.addChannel(instrumentName, "count", channels(channelIdx));
end
engine = measurementEngine.fromRack(rack);
cleanupObj = onCleanup(@() delete(engine));
rack.rackSet(channels, [1; 2; 3]);

try
    smstrainwarmup();
    error("test_smstrainwarmup_client_sequence:ExpectedMissingHandle", ...
        "Expected the fake rack to lack handle_strainController.");
catch ME
    assert(contains(ME.message, "handle_strainController"), ...
        "Unexpected final warmup error: %s", ME.message);
end
assert(all(abs(rack.rackGet(channels)) < 1E-9), ...
    "smstrainwarmup did not set/check all strain-cell channels before final warmup.");

disp("PASS: client strain warmup zeros and checks channels before final engine warmup.");
