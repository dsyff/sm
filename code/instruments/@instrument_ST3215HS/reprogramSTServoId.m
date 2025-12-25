function reprogramSTServoId(comPort, idFrom, idTo, NameValueArgs)
%reprogramSTServoId Reprogram a Waveshare STS bus-servo ID (persistent EPROM)
%
% This implements the vendor flow shown in:
%   temp/waveshare servo/ST Servo/SCServo/examples/STSCL/ProgramEprom/ProgramEprom.ino
%
% Call as a static utility:
%   instrument_ST3215HS.reprogramSTServoId("COM3", 1, 2);
%
% Steps:
%   1) unlock EPROM on old ID (write 0 to SMS_STS_LOCK)
%   2) write new ID to SMS_STS_ID (EPROM)
%   3) lock EPROM on new ID (write 1 to SMS_STS_LOCK)
%
% Notes:
% - Make sure ONLY ONE servo with idFrom is connected when you do this.
% - After step (2), the servo will start responding on idTo.

arguments
    comPort (1, 1) string {mustBeNonzeroLengthText}
    idFrom (1, 1) double {mustBeInteger, mustBePositive}
    idTo (1, 1) double {mustBeInteger, mustBePositive}
    NameValueArgs.baudRate (1, 1) double {mustBePositive, mustBeInteger} = 1000000
    NameValueArgs.timeoutSeconds (1, 1) double {mustBePositive} = 0.2
    NameValueArgs.verbose (1, 1) logical = true
end

idFrom8 = uint8(idFrom);
idTo8 = uint8(idTo);

% SMS_STS.h EPROM map
SMS_STS_ID = uint8(5);
SMS_STS_LOCK = uint8(55);

% INST.h
INST_WRITE = uint8(hex2dec("03"));

sp = serialport(comPort, NameValueArgs.baudRate, Timeout = NameValueArgs.timeoutSeconds);
cleanup = onCleanup(@() safeClose_(sp)); %#ok<NASGU>
sp.FlowControl = "none";

if NameValueArgs.verbose
    fprintf("Reprogramming STS servo ID on %s @ %d baud: %d -> %d\n", comPort, NameValueArgs.baudRate, idFrom, idTo);
end

% 1) unlock EPROM on old ID
flush(sp);
sendWriteByte_(sp, idFrom8, INST_WRITE, SMS_STS_LOCK, uint8(0));
readAck_(sp, idFrom8);
if NameValueArgs.verbose
    fprintf("  EPROM unlocked on ID %d\n", idFrom);
end

% 2) write new ID to EPROM (writeByte to SMS_STS_ID)
flush(sp);
sendWriteByte_(sp, idFrom8, INST_WRITE, SMS_STS_ID, idTo8);
readAck_(sp, idFrom8);
if NameValueArgs.verbose
    fprintf("  Wrote new ID value (%d) via old ID %d\n", idTo, idFrom);
end

% 3) lock EPROM on NEW ID (vendor example locks with the new ID)
flush(sp);
sendWriteByte_(sp, idTo8, INST_WRITE, SMS_STS_LOCK, uint8(1));
readAck_(sp, idTo8);
if NameValueArgs.verbose
    fprintf("  EPROM locked on new ID %d\n", idTo);
    fprintf("Done.\n");
end

end

%% ---- local helpers ----
function sendWriteByte_(sp, id, instWrite, memAddr, valueByte)
    id = uint8(id);
    instWrite = uint8(instWrite);
    memAddr = uint8(memAddr);
    payload = uint8(valueByte);

    % writeBuf framing (Waveshare SCS::writeBuf)
    % LEN = 2 + (1 + payloadLen)
    msgLen = uint8(2 + 1 + numel(payload));
    checksum = uint16(id) + uint16(msgLen) + uint16(instWrite) + uint16(memAddr) + sum(uint16(payload));
    checksumByte = bitcmp(uint8(mod(checksum, 256)));

    pkt = [uint8(255), uint8(255), id, msgLen, instWrite, memAddr, payload, checksumByte];
    write(sp, pkt, "uint8");
end

function readAck_(sp, expectedId)
    % Mirrors SCS::Ack(): header 0xFF 0xFF then [ID LEN ERR CHK], LEN must be 2.
    expectedId = uint8(expectedId);

    % Find 0xFF 0xFF header
    prev = uint8(0);
    cur = uint8(0);
    for k = 1:50
        b = read(sp, 1, "uint8");
        if isempty(b)
            error("Timeout waiting for ACK header (0xFF 0xFF) for ID %d.", expectedId);
        end
        prev = cur;
        cur = b(1);
        if prev == uint8(255) && cur == uint8(255)
            break;
        end
        if k == 50
            error("ACK header not found for ID %d.", expectedId);
        end
    end

    hdr = read(sp, 4, "uint8"); % [ID LEN ERR CHK]
    if numel(hdr) ~= 4
        error("Timeout reading ACK bytes for ID %d.", expectedId);
    end

    id = hdr(1);
    len = hdr(2);
    err = hdr(3);
    chk = hdr(4);

    if id ~= expectedId
        error("ACK ID mismatch. Expected %d, got %d.", expectedId, id);
    end
    if len ~= uint8(2)
        error("ACK length mismatch. Expected 2, got %d.", len);
    end

    cal = bitcmp(uint8(mod(uint16(id) + uint16(len) + uint16(err), 256)));
    if cal ~= chk
        error("ACK checksum mismatch for ID %d.", expectedId);
    end
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


