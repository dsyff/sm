classdef instrument_colorLED < instrumentInterface
    % USB CDC WS2811 color LED controller

    properties (Access = private)
        cachedRgb double = [0; 0; 0];
    end

    methods
        function obj = instrument_colorLED(address)
            obj@instrumentInterface();
            handle = serialport(address, 115200, Timeout = 1);
            configureTerminator(handle, "CR/LF", "LF");
            flush(handle);

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("R");
            obj.addChannel("G");
            obj.addChannel("B");
            obj.addChannel("RGB", 3);

            obj.requireSetCheck = false;
            obj.cachedRgb = obj.queryRgb();
        end

        function delete(obj)
            if ~isempty(obj.communicationHandle) && isvalid(obj.communicationHandle)
                flush(obj.communicationHandle);
                delete(obj.communicationHandle);
            end
        end

        function flush(obj)
            flush(obj.communicationHandle);
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, ~)
            writeline(obj.communicationHandle, "GET");
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            response = strip(readline(obj.communicationHandle));
            rgb = obj.parseRgbResponse(response);
            obj.cachedRgb = rgb;
            switch channelIndex
                case 1
                    getValues = rgb(1);
                case 2
                    getValues = rgb(2);
                case 3
                    getValues = rgb(3);
                case 4
                    getValues = rgb;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if any(setValues < 0 | setValues > 1)
                error("instrument_colorLED:ValueOutOfRange", "R/G/B values must be in [0,1].");
            end

            rgb = obj.cachedRgb;
            switch channelIndex
                case 1
                    rgb(1) = setValues(1);
                case 2
                    rgb(2) = setValues(1);
                case 3
                    rgb(3) = setValues(1);
                case 4
                    rgb = setValues;
            end

            rgbInt = round(rgb * 255);
            command = compose("COLOR %d,%d,%d", rgbInt(1), rgbInt(2), rgbInt(3));
            writeline(obj.communicationHandle, command);
            response = strip(readline(obj.communicationHandle));
            if ~strcmpi(response, "OK")
                error("instrument_colorLED:CommandFailed", "COLOR command failed with response: " + response);
            end

            obj.cachedRgb = rgbInt(:) / 255;
        end
    end

    methods (Access = private)
        function rgb = queryRgb(obj)
            writeline(obj.communicationHandle, "GET");
            response = strip(readline(obj.communicationHandle));
            rgb = obj.parseRgbResponse(response);
        end

        function rgb = parseRgbResponse(~, response)
            if ~startsWith(upper(response), "COLOR")
                error("instrument_colorLED:BadResponse", "Expected COLOR response, received: " + response);
            end

            numbers = regexp(response, "\d+", "match");
            if numel(numbers) ~= 3
                error("instrument_colorLED:BadResponse", "Expected 3 color values, received: " + response);
            end

            rgbInt = str2double(numbers);
            if any(isnan(rgbInt)) || any(rgbInt < 0 | rgbInt > 255)
                error("instrument_colorLED:BadResponse", "Color values must be integers 0..255. Received: " + response);
            end
            rgb = rgbInt(:) / 255;
        end
    end
end
