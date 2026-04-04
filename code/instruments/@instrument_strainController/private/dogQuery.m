function reply = dogQuery(handle_strainWatchdog, command, timeout)
arguments
    handle_strainWatchdog (1, 1) instrumentWorker
    command;
    timeout duration = seconds(5);
end

reply = handle_strainWatchdog.instQueryInstWorker(command, timeout);
end
