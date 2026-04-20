classdef instrument_Montana1 < instrumentInterface
    % Thomas 20241221
    properties (Access = private)
        % class variables go here
        urlRoot
        platformGetUrl;
        platformSetUrl;
        readValues;
        approachTime;
        defaultWeboptions = weboptions(Timeout = 3);
        highTemperatureLimit (1,1) double = 300;
    end

    methods

        function obj = instrument_Montana1(address)
            obj@instrumentInterface();
            obj.urlRoot = sprintf("http://%s:47101/v1", address);
            obj.platformGetUrl = obj.urlRoot + "/sampleChamber/temperatureControllers/platform/thermometer/properties/sample";
            obj.platformSetUrl = obj.urlRoot + "/controller/properties/platformTargetTemperature";

            % assign object properties
            obj.address = address;

            obj.addChannel("T");
        end

        function cooldown(obj)
            data = struct("dryNitrogenPurgeEnabled", 1);
            obj.webput(obj.urlRoot + "/controller/properties/dryNitrogenPurgeEnabled", data);
            data = struct("dryNitrogenPurgeNumTimes", 5);
            obj.webput(obj.urlRoot + "/controller/properties/dryNitrogenPurgeNumTimes", data);
            data = struct("platformBakeoutEnabled", 0);
            obj.webput(obj.urlRoot + "/controller/properties/platformBakeoutEnabled", data);
            obj.webpost(obj.urlRoot + "/controller/methods/abortGoal()");
            obj.webpost(obj.urlRoot + "/controller/methods/cooldown()");
        end

        function warmup(obj)
            obj.webpost(obj.urlRoot + "/controller/methods/abortGoal()");
            obj.webpost(obj.urlRoot + "/controller/methods/warmup()");
        end

        function currentTarget = getCurrentTargetTemperature(obj)
            currentTarget = webread(obj.platformSetUrl, obj.defaultWeboptions).platformTargetTemperature;
        end
    end

    
    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    obj.readValues = webread(obj.platformGetUrl, obj.defaultWeboptions).sample.temperatureAvg1Sec;
            end
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            switch channelIndex
                case 1
                    getValues = obj.readValues;
            end
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            switch channelIndex
                case 1
                    data.platformTargetTemperature = setValues;
                    obj.webput(obj.platformSetUrl, data);
            end
            obj.approachTime = datetime('now');
        end

        function TF = setCheckChannelHelper(obj, channelIndex, channelLastSetValues)
            targetTemperature = channelLastSetValues;
            if obj.enforceTargetTemperature(targetTemperature)
                warning("Montana target temperature was changed elsewhere.");
            end
            actualTemperature = obj.getChannelByIndex(channelIndex);
            absDiff = abs(targetTemperature - actualTemperature);
            if targetTemperature < 3.9
                if actualTemperature > 4
                    obj.approachTime = datetime('now');
                end
            elseif targetTemperature < 15
                if absDiff > 0.5
                    obj.approachTime = datetime('now');
                end
            elseif targetTemperature <= obj.highTemperatureLimit
                if absDiff > 0.2
                    obj.approachTime = datetime('now');
                end
            else
                if actualTemperature <= (obj.highTemperatureLimit - 1)
                    obj.approachTime = datetime('now');
                end
            end
            stabilizingTime = datetime('now') - obj.approachTime;
            if targetTemperature < 3.9
                TF = stabilizingTime > minutes(0.5);
            elseif targetTemperature < 15
                TF = absDiff < 0.1 || stabilizingTime > minutes(5);
            elseif targetTemperature <= obj.highTemperatureLimit
                TF = absDiff < 0.1 || stabilizingTime > minutes(5);
            else
                TF = stabilizingTime > minutes(15);
                if TF && absDiff > 1
                    Warning("Montana 1 failed to reach %fK", targetTemperature);
                end
            end
        end

    end

    methods (Access = private)

        function webpost(obj, url)
            options = obj.defaultWeboptions;
            options.RequestMethod = "post";
            webwrite(url, options);
        end

        function webput(obj, url, data)
            options = obj.defaultWeboptions;
            options.RequestMethod = "put";
            webwrite(url, data, options);
        end
        
        function targetChanged = enforceTargetTemperature(obj, targetTemperature)
            % sets temperature if current target differs from
            % targetTemperature
            currentTarget = obj.getCurrentTargetTemperature();
            targetChanged = currentTarget ~= targetTemperature;
            if abs(currentTarget - targetTemperature) > 0.001
                obj.setWriteChannel("T", targetTemperature);
            end
        end
    end

end
