function dogSend(handle_strainWatchdog, command)
arguments
    handle_strainWatchdog (1, 1) instrumentWorker
    command
end

handle_strainWatchdog.instSendToInstWorker(command);
end
