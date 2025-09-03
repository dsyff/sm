function dogSend(handle_strainWatchdog, command)
arguments
    handle_strainWatchdog;
    command (1, 1) string;
end

% flush queue
dogFlush(handle_strainWatchdog);

man2Dog = handle_strainWatchdog.man2Dog;
%dog2Man = handle_strainWatchdog.dog2Man;
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

end