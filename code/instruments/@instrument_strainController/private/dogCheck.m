function TF = dogCheck(handle_strainWatchdog, channel, timeout)
arguments
    handle_strainWatchdog;
    channel (1, 1) string;
    timeout duration = seconds(5);
end
command.channel = channel;
command.action = "CHECK";
reply = dogQuery(handle_strainWatchdog, command, timeout);

if islogical(reply)
    TF = reply;
else
    Error("Logical expected for dogCheck. Received: \n%s", formattedDisplayText(reply));
end
end