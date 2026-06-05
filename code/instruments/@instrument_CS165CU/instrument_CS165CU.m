classdef instrument_CS165CU < instrument_CS165MU
    % instrument_CS165CU
    % Thorlabs CS165CU color camera using raw Bayer-plane extraction.

    properties
        colorChannel (1, 1) string {mustBeMember(colorChannel, ["red", "green", "blue", "gray", "rgb"])} = "red"
        bayerPattern (1, 1) string {mustBeMember(bayerPattern, ["RGGB", "BGGR", "GRBG", "GBRG"])} = "RGGB"
    end

    properties (Access = private)
        pendingColorValue double = NaN;
    end

    methods
        function obj = instrument_CS165CU(address)
            arguments
                address (1, 1) string = "";
            end

            obj@instrument_CS165MU(address);
            obj.isColorCamera = true;
            obj.addChannel("color"); % 0 red, 1 green, 2 blue, 3 gray, 4 RGB live view/acquisition
        end

        function setAcquisitionColorChannel(obj, colorChannel)
            arguments
                obj
                colorChannel (1, 1) string
            end

            colorChannel = lower(colorChannel);
            if ~ismember(colorChannel, ["red", "green", "blue", "gray", "rgb"])
                error("instrument_CS165CU:InvalidColorChannel", ...
                    "colorChannel must be red, green, blue, gray, or rgb.");
            end
            obj.colorChannel = colorChannel;
        end

        function colorChannel = getAcquisitionColorChannel(obj)
            colorChannel = obj.colorChannel;
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            if channelIndex == 9
                obj.pendingColorValue = obj.colorChannelToValue(obj.colorChannel);
            else
                obj.getWriteCameraChannelHelper(channelIndex);
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            if channelIndex == 9
                getValues = obj.pendingColorValue;
                obj.pendingColorValue = NaN;
            else
                getValues = obj.getReadCameraChannelHelper(channelIndex);
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            if channelIndex == 9
                obj.colorChannel = obj.valueToColorChannel(setValues(1));
            else
                obj.setWriteCameraChannelHelper(channelIndex, setValues);
            end
        end
    end

    methods (Access = protected)
        function image2D = frameToImage2D(obj, imageFrame)
            rawImage = frameToImage2D@instrument_CS165MU(obj, imageFrame);
            image2D = obj.extractSelectedBayerPlane(rawImage);
        end
    end

    methods (Access = private)
        function image2D = extractSelectedBayerPlane(obj, rawImage)
            if any(mod(size(rawImage), 2) ~= 0)
                error("instrument_CS165CU:OddBayerFrameSize", ...
                    "CS165CU Bayer extraction requires even frame height and width. Received [%d %d].", ...
                    size(rawImage, 1), size(rawImage, 2));
            end

            pattern = obj.currentFrameBayerPattern();
            switch obj.colorChannel
                case "red"
                    image2D = obj.expandSingleColor(rawImage, pattern, 'R');
                case "green"
                    image2D = obj.expandGreen(rawImage, pattern);
                case "blue"
                    image2D = obj.expandSingleColor(rawImage, pattern, 'B');
                case "gray"
                    red = obj.expandSingleColor(rawImage, pattern, 'R');
                    green = obj.expandGreen(rawImage, pattern);
                    blue = obj.expandSingleColor(rawImage, pattern, 'B');
                    image2D = uint16(round((double(red) + 2 * double(green) + double(blue)) / 4));
                case "rgb"
                    image2D = cat(3, obj.expandSingleColor(rawImage, pattern, 'R'), obj.expandGreen(rawImage, pattern), obj.expandSingleColor(rawImage, pattern, 'B'));
            end
        end

        function pattern = currentFrameBayerPattern(obj)
            switch obj.bayerPattern
                case "RGGB"
                    pattern = ['R' 'G'; 'G' 'B'];
                case "BGGR"
                    pattern = ['B' 'G'; 'G' 'R'];
                case "GRBG"
                    pattern = ['G' 'R'; 'B' 'G'];
                case "GBRG"
                    pattern = ['G' 'B'; 'R' 'G'];
            end

            [xOrigin, yOrigin] = obj.getCurrentRoiOriginPixels();
            pattern = circshift(pattern, [-mod(round(yOrigin), 2), -mod(round(xOrigin), 2)]);
        end

        function image2D = expandSingleColor(~, rawImage, pattern, colorCode)
            [rowInCell, colInCell] = find(pattern == colorCode, 1);
            if isempty(rowInCell)
                error("instrument_CS165CU:InvalidBayerPattern", ...
                    "Bayer pattern does not contain color %s.", string(colorCode));
            end
            samples = rawImage(rowInCell:2:end, colInCell:2:end);
            image2D = repelem(samples, 2, 2);
        end

        function image2D = expandGreen(~, rawImage, pattern)
            [rowInCell, colInCell] = find(pattern == 'G');
            if numel(rowInCell) ~= 2
                error("instrument_CS165CU:InvalidBayerPattern", ...
                    "Bayer pattern must contain exactly two green pixels.");
            end
            samplesA = rawImage(rowInCell(1):2:end, colInCell(1):2:end);
            samplesB = rawImage(rowInCell(2):2:end, colInCell(2):2:end);
            samples = uint16(round((double(samplesA) + double(samplesB)) / 2));
            image2D = repelem(samples, 2, 2);
        end

        function colorValue = colorChannelToValue(~, colorChannel)
            switch colorChannel
                case "red"
                    colorValue = 0;
                case "green"
                    colorValue = 1;
                case "blue"
                    colorValue = 2;
                case "gray"
                    colorValue = 3;
                case "rgb"
                    colorValue = 4;
            end
        end

        function colorChannel = valueToColorChannel(~, colorValue)
            if ~isfinite(colorValue) || colorValue ~= round(colorValue) || colorValue < 0 || colorValue > 4
                error("instrument_CS165CU:InvalidColorValue", ...
                    "color channel must be 0 red, 1 green, 2 blue, 3 gray, or 4 rgb.");
            end
            channels = ["red", "green", "blue", "gray", "rgb"];
            colorChannel = channels(colorValue + 1);
        end
    end
end
