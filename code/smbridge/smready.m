function smready(source, options)
%SMREADY Initialize measurement engine and launch SM GUIs.

arguments
    source (1, 1)
    options.singleThreaded (1, 1) logical = false
    options.verboseClient (1, 1) logical = false
    options.verboseWorker (1, 1) logical = false
    options.workerLogFile (1, 1) string = ""
    options.clientLogFile (1, 1) string = ""
    options.experimentRootPath {mustBeTextScalar} = ""
end

global engine smscan smaux smdata bridge %#ok<GVMIS,NUSED>

if ~(isa(source, "instrumentRack") || isa(source, "instrumentRackRecipe"))
    error("smready:InvalidInput", "smready expects instrumentRack or instrumentRackRecipe.");
end

if isa(source, "instrumentRack")
    engine = measurementEngine.fromRack(source, ...
        verboseClient = options.verboseClient, ...
        clientLogFile = options.clientLogFile, ...
        experimentRootPath = string(options.experimentRootPath));
else
    engine = measurementEngine(source, ...
        singleThreaded = options.singleThreaded, ...
        verboseClient = options.verboseClient, ...
        verboseWorker = options.verboseWorker, ...
        workerLogFile = options.workerLogFile, ...
        clientLogFile = options.clientLogFile, ...
        experimentRootPath = string(options.experimentRootPath));
end
engine.printRack();

bridge = smguiBridge(engine);
bridge.initializeSmdata();

smgui_small();
sm;
end
