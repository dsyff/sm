function handle_strainWatchdog = strainWatchdogConstructor(options)
arguments
    options.address_E4980AL (1, 1) string = gpibAddress(6);
    options.address_K2450_A (1, 1) string = gpibAddress(17);
    options.address_K2450_B (1, 1) string = gpibAddress(18);
    options.address_Montana2 (1, 1) string = "136.167.55.165";
    options.address_Opticool (1, 1) string = "127.0.0.1";
    options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "Opticool"])};
    options.strainCellNumber (2, 2) uint8 {mustBeInteger, mustBePositive};
end

%%
assert(~isMATLABReleaseOlderThan("R2022a"), "Matlab version is too old");
currentPool = (gcp('nocreate'));
assert(~isempty(currentPool), "No Parallel pool found. Please create one in main script");

%%
dog2Man = parallel.pool.PollableDataQueue;
dogFuture = parfeval(@strainWatchdog, 0, dog2Man, ...
    address_E4980AL = options.address_E4980AL, ...
    address_K2450_A = options.address_K2450_A, ...
    address_K2450_B = options.address_K2450_B, ...
    address_Montana2 = options.address_Montana2, ...
    address_Opticool = options.address_Opticool, ...
    cryostat = options.cryostat, ...
    strainCellNumber = options.strainCellNumber);

%% obtain man2Dog channel
pause(2);
while dog2Man.QueueLength == 0
    if ~matches(dogFuture.State, "running")
        try
            rethrow(dogFuture.Error.remotecause{1});
        catch
            error("Strain watch dog did not start successfully. State: %s", dogFuture.State);
        end
        %break;
    end
end
man2Dog = poll(dog2Man);
pause(5);
%%
handle_strainWatchdog.man2Dog = man2Dog;
handle_strainWatchdog.dog2Man = dog2Man;
handle_strainWatchdog.dogFuture = dogFuture;
end