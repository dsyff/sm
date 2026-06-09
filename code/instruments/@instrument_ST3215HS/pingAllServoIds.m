function ids = pingAllServoIds(comPort, NameValueArgs)
%pingAllServoIds Scan Waveshare ST/SCS bus servo IDs without constructing the instrument.
%
% Direct Waveshare Bus Servo Adapter (A):
%   ids = instrument_ST3215HS.pingAllServoIds("COM4");
%
% ESP32 driver board serial-forwarding mode:
%   ids = instrument_ST3215HS.pingAllServoIds("COM4", baudRate = 115200);

arguments
    comPort (1, 1) string {mustBeNonzeroLengthText}
    NameValueArgs.baudRate (1, 1) double {mustBePositive, mustBeInteger} = 1000000
    NameValueArgs.idRange (1, :) double {mustBeInteger} = 0:253
    NameValueArgs.responseTimeoutSeconds (1, 1) double {mustBePositive} = 0.05
    NameValueArgs.verbose (1, 1) logical = true
end

idRange = double(NameValueArgs.idRange);
if any(idRange < 0 | idRange > 253)
    error("ST3215HS:InvalidServoId", "idRange entries must be in the range 0..253.");
end

sp = serialport(comPort, NameValueArgs.baudRate, Timeout = 0.01);
cleanup = onCleanup(@() safeClose_(sp));
sp.FlowControl = "none";
flush(sp);

ids = [];
if NameValueArgs.verbose
    experimentContext.print("Pinging %d servo IDs on %s @ %d baud", numel(idRange), comPort, NameValueArgs.baudRate);
end

for id = idRange
    id8 = uint8(id);
    flush(sp, "input");
    pingBody = uint8([id8, 2, 1]);
    write(sp, [uint8([255, 255]), pingBody, checksum_(pingBody)], "uint8");

    response = readPingAck_(sp, id8, NameValueArgs.responseTimeoutSeconds);
    if ~isempty(response)
        ids(end + 1) = double(response(1)); %#ok<AGROW>
        if NameValueArgs.verbose
            experimentContext.print("  FOUND servo ID %d", response(1));
        end
    end
end

if NameValueArgs.verbose
    experimentContext.print("Done. Responding IDs: %s", mat2str(ids));
end
end

function response = readPingAck_(sp, expectedId, timeoutSeconds)
    response = uint8([]);
    prev = uint8(0);
    t0 = tic;
    echoBody = uint8([expectedId, 2, 1, checksum_(uint8([expectedId, 2, 1]))]);

    while toc(t0) < timeoutSeconds
        if sp.NumBytesAvailable == 0
            pause(0.001);
            continue;
        end

        cur = read(sp, 1, "uint8");
        cur = cur(1);
        if cur == uint8(255) && prev == uint8(255)
            idLen = readExactAvailable_(sp, 2, timeoutSeconds - toc(t0));
            if isempty(idLen)
                error("ST3215HS:PingAckTimeout", "Saw PING ACK header but not ID/LEN bytes.");
            end
            if idLen(2) ~= uint8(2)
                error("ST3215HS:AckLenMismatch", "PING ACK length mismatch. Expected 2, got %d.", idLen(2));
            end

            rest = readExactAvailable_(sp, 2, timeoutSeconds - toc(t0));
            if isempty(rest)
                error("ST3215HS:PingAckTimeout", "Saw PING ACK header but packet was incomplete.");
            end

            packet = [idLen, rest];
            if packet(end) ~= checksum_(packet(1:end-1))
                error("ST3215HS:AckChecksumMismatch", "PING ACK checksum mismatch.");
            end
            if isequal(packet, echoBody)
                prev = uint8(0);
                continue;
            end
            if packet(1) ~= expectedId
                error("ST3215HS:AckIdMismatch", ...
                    "PING ACK ID mismatch. Expected %d, got %d.", expectedId, packet(1));
            end

            response = packet; % [ID LEN ERR CHECKSUM]
            return;
        end
        prev = cur;
    end
end

function data = readExactAvailable_(sp, nBytes, timeoutSeconds)
    data = uint8([]);
    t0 = tic;
    while numel(data) < nBytes && toc(t0) < timeoutSeconds
        available = sp.NumBytesAvailable;
        if available == 0
            pause(0.001);
            continue;
        end
        chunk = read(sp, min(nBytes - numel(data), available), "uint8");
        data = [data, reshape(uint8(chunk), 1, [])]; %#ok<AGROW>
    end
    if numel(data) ~= nBytes
        data = uint8([]);
    end
end

function c = checksum_(bytes)
    c = bitcmp(uint8(mod(sum(uint16(bytes)), 256)));
end

function safeClose_(sp)
    try
        flush(sp);
    catch
    end
    try
        delete(sp);
    catch
    end
end
