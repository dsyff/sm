function dogFlush(handle_strainWatchdog)

dog2Man = handle_strainWatchdog.dog2Man;

while dog2Man.QueueLength > 0
    warning("Non-empty dog2Man queue. Received:");
    reply = poll(dog2Man);
    if isempty(reply)
        error("empty reply received from strainWatchdog");
    elseif isstring(reply) && startsWith(reply, "Error", "IgnoreCase", true)
        error(reply);
    elseif isa(reply, "MException")
        rethrow(reply);
    else
        experimentContext.print(reply);
    end
end

end