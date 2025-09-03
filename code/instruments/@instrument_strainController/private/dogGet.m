function reply = dogGet(handle_strainWatchdog, channel, timeout)
arguments
    handle_strainWatchdog;
    channel (1, 1) string;
    timeout duration = seconds(5);
end
command.channel = channel;
command.action = "GET";
reply = dogQuery(handle_strainWatchdog, command, timeout);
end