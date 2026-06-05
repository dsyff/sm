classdef instrument_colorLED < instrumentInterface
    % USB CDC WS2811 color LED controller

    properties (Access = private)
        cachedRGB double = [0; 0; 0];
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
            obj.cachedRGB = obj.queryRGB();
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
            RGB = obj.parseRGBResponse(response);
            obj.cachedRGB = RGB;
            switch channelIndex
                case 1
                    getValues = RGB(1);
                case 2
                    getValues = RGB(2);
                case 3
                    getValues = RGB(3);
                case 4
                    getValues = RGB;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if any(setValues < 0 | setValues > 1)
                error("instrument_colorLED:ValueOutOfRange", "R/G/B values must be in [0,1].");
            end

            RGB = obj.cachedRGB;
            switch channelIndex
                case 1
                    RGB(1) = setValues(1);
                case 2
                    RGB(2) = setValues(1);
                case 3
                    RGB(3) = setValues(1);
                case 4
                    RGB = setValues;
            end

            RGBInt = round(RGB * 255);
            command = compose("COLOR %d,%d,%d", RGBInt(1), RGBInt(2), RGBInt(3));
            writeline(obj.communicationHandle, command);
            response = strip(readline(obj.communicationHandle));
            if ~strcmpi(response, "OK")
                error("instrument_colorLED:CommandFailed", "COLOR command failed with response: " + response);
            end

            obj.cachedRGB = RGBInt(:) / 255;
        end
    end

    methods (Access = private)
        function RGB = queryRGB(obj)
            writeline(obj.communicationHandle, "GET");
            response = strip(readline(obj.communicationHandle));
            RGB = obj.parseRGBResponse(response);
        end

        function RGB = parseRGBResponse(~, response)
            if ~startsWith(upper(response), "COLOR")
                error("instrument_colorLED:BadResponse", "Expected COLOR response, received: " + response);
            end

            numbers = regexp(response, "\d+", "match");
            if numel(numbers) ~= 3
                error("instrument_colorLED:BadResponse", "Expected 3 color values, received: " + response);
            end

            RGBInt = str2double(numbers);
            if any(isnan(RGBInt)) || any(RGBInt < 0 | RGBInt > 255)
                error("instrument_colorLED:BadResponse", "Color values must be integers 0..255. Received: " + response);
            end
            RGB = RGBInt(:) / 255;
        end
    end
end
