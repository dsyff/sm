function reply = dogQuery(handle_strainWatchdog, command, timeout)
arguments
    handle_strainWatchdog;
    command;
    timeout duration = seconds(5);
end

% flush queue
dogFlush(handle_strainWatchdog);

man2Dog = handle_strainWatchdog.man2Dog;
dog2Man = handle_strainWatchdog.dog2Man;
dogFuture = handle_strainWatchdog.dogFuture;
if dogFuture.State ~= "running"
    if isprop(dogFuture, "Error") && ~isempty(dogFuture.Error)
        throw(dogFuture.Error);
    else
        error("strainWatchdog is not running");
    end
end

% send command
send(man2Dog, command);
startTime = datetime("now");
while dog2Man.QueueLength == 0
    if ~matches(dogFuture.State, "running")
        if isprop(dogFuture.Error, "remotecause")
            rethrow(dogFuture.Error.remotecause{1});
        else
            rethrow(dogFuture.Error);
        end
    end
    assert(datetime("now") - startTime < timeout, "strainWatchdog did not respond in time");
end
reply = poll(dog2Man);
if isempty(reply)
    error("empty reply received from strainWatchdog");
elseif isstring(reply) && startsWith(reply, "Error", "IgnoreCase", true)
    error(reply);
elseif isa(reply, "MException")
    rethrow(reply);
end
end