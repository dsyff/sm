function handle_strainWatchdog = strainWatchdogConstructor(options)
arguments
    options.address_E4980AL (1, 1) string = gpibAddress(6);
    options.address_K2450_A (1, 1) string = gpibAddress(17);
    options.address_K2450_B (1, 1) string = gpibAddress(18);
    options.address_Montana2 (1, 1) string = "136.167.55.165";
    options.address_OptiCool (1, 1) string = "127.0.0.1";
    options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "OptiCool"])};
    options.strainCellNumber (1, 1) uint8 {mustBeInteger, mustBePositive};
    options.experimentRootPath {mustBeTextScalar} = ""
    options.spawnFcn = [];
end

%%
assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");

%%
dog2Man = parallel.pool.PollableDataQueue;
dogFuture = [];
spawnFcn = options.spawnFcn;
if isempty(spawnFcn)
    spawnOnClient = [];
    try
        spawnOnClient = evalin("base", "sm_spawnOnClient");
    catch
    end
    if isa(spawnOnClient, "function_handle")
        spawnFcn = @(fcn, nOut, varargin) spawnOnClient("strainWatchdog", fcn, nOut, varargin{:});
    end
end

rootPath = string(options.experimentRootPath);
if strlength(rootPath) == 0
    rootPath = experimentContext.getExperimentRootPath();
end
if strlength(rootPath) == 0
    rootPath = string(pwd);
end

if ~isempty(spawnFcn)
    if ~isa(spawnFcn, "function_handle")
        error("strainWatchdogConstructor:InvalidSpawnFcn", "spawnFcn must be a function_handle.");
    end
    spawnFcn(@strainWatchdog, 0, dog2Man, ...
        address_E4980AL = options.address_E4980AL, ...
        address_K2450_A = options.address_K2450_A, ...
        address_K2450_B = options.address_K2450_B, ...
        address_Montana2 = options.address_Montana2, ...
        address_OptiCool = options.address_OptiCool, ...
        cryostat = options.cryostat, ...
        strainCellNumber = options.strainCellNumber, ...
        experimentRootPath = rootPath);
elseif ~isempty(getCurrentTask())
    requestWorkerSpawn("strainWatchdog", @strainWatchdog, 0, dog2Man, ...
        address_E4980AL = options.address_E4980AL, ...
        address_K2450_A = options.address_K2450_A, ...
        address_K2450_B = options.address_K2450_B, ...
        address_Montana2 = options.address_Montana2, ...
        address_OptiCool = options.address_OptiCool, ...
        cryostat = options.cryostat, ...
        strainCellNumber = options.strainCellNumber, ...
        experimentRootPath = rootPath);
else
    dogFuture = parfeval(@strainWatchdog, 0, dog2Man, ...
        address_E4980AL = options.address_E4980AL, ...
        address_K2450_A = options.address_K2450_A, ...
        address_K2450_B = options.address_K2450_B, ...
        address_Montana2 = options.address_Montana2, ...
        address_OptiCool = options.address_OptiCool, ...
        cryostat = options.cryostat, ...
        strainCellNumber = options.strainCellNumber, ...
        experimentRootPath = rootPath);
end

%% obtain man2Dog channel
pause(2); % allow worker init to start
handshakeTimeout = seconds(60);
startTime = datetime("now");
while dog2Man.QueueLength == 0
    if ~isempty(dogFuture) && ~matches(dogFuture.State, "running")
        try
            rethrow(dogFuture.Error.remotecause{1});
        catch
            error("Strain watch dog did not start successfully. State: %s", dogFuture.State);
        end
    end
    assert(datetime("now") - startTime < handshakeTimeout, "Strain watch dog did not start successfully (timeout).");
    pause(1E-6);
end
man2Dog = poll(dog2Man);
pause(5);
%%
handle_strainWatchdog.man2Dog = man2Dog;
handle_strainWatchdog.dog2Man = dog2Man;
handle_strainWatchdog.dogFuture = dogFuture;
end
