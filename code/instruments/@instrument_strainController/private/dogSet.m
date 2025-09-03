function dogSet(handle_strainWatchdog, channel, val, timeout)
arguments
    handle_strainWatchdog;
    channel (1, 1) string;
    val;
    timeout duration = seconds(5);
end
command.channel = channel;
command.action = "SET";
command.value = val;
reply = dogQuery(handle_strainWatchdog, command, timeout);

if ~islogical(reply) || ~reply
    error("True logical expected for successful dogSet. Received: \n%s", formattedDisplayText(reply));
end
end