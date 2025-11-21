classdef instrument_strainController < instrumentInterface
    properties (Access = private)
        handle_strainWatchdog   % struct with man2Dog, dog2Man, dogFuture
        channels string = ["del_d", "T", "Cp", "Q", "C", "d", ...
            "V_str_o", "V_str_i", "I_str_o", "I_str_i", "activeControl"];
        dogGetTimeout duration = seconds(15);
        dogCheckTimeout duration = seconds(60);
        rack_strainController string = "";
    end

    properties (Access = protected)
        version = "1.4"; %202500903
    end

    methods
        function obj = instrument_strainController(address, options)
            arguments
                address (1,1) string = "strainController_1"
                options.address_E4980AL (1, 1) string = gpibAddress(6)
                options.address_K2450_A (1, 1) string = gpibAddress(17)
                options.address_K2450_B (1, 1) string = gpibAddress(18)
                options.address_Montana2 (1, 1) string = "136.167.55.165"
                options.address_Opticool (1, 1) string = "127.0.0.1"
                options.cryostat (1, 1) string {mustBeMember(options.cryostat, ["Montana2", "Opticool"])}
                options.strainCellNumber (1, 1) uint8 {mustBeInteger, mustBePositive}
            end

            obj@instrumentInterface();

            handle = strainWatchdogConstructor( ...
                address_E4980AL = options.address_E4980AL, ...
                address_K2450_A = options.address_K2450_A, ...
                address_K2450_B = options.address_K2450_B, ...
                address_Montana2 = options.address_Montana2, ...
                address_Opticool = options.address_Opticool, ...
                cryostat = options.cryostat, ...
                strainCellNumber = options.strainCellNumber ...
            );
            obj.handle_strainWatchdog = handle;

            dogSet(obj.handle_strainWatchdog, "V_str_o", 0);
            dogSet(obj.handle_strainWatchdog, "V_str_i", 0);
            dogSet(obj.handle_strainWatchdog, "frequency", 100E3);

            if options.cryostat == "Opticool"
                % dogSet(obj.handle_strainWatchdog, "Z_short_r", 5.68);
                % dogSet(obj.handle_strainWatchdog, "Z_short_theta", deg2rad(22.2));
                % dogSet(obj.handle_strainWatchdog, "Z_open_r", 28.9E6);
                % dogSet(obj.handle_strainWatchdog, "Z_open_theta", deg2rad(106.7));
                %20250904 internal calibration all on
                dogSet(obj.handle_strainWatchdog, "Z_short_r", 5.56);
                dogSet(obj.handle_strainWatchdog, "Z_short_theta", deg2rad(20.5));
                dogSet(obj.handle_strainWatchdog, "Z_open_r", 27.9E6);
                dogSet(obj.handle_strainWatchdog, "Z_open_theta", deg2rad(104.2));
            elseif options.cryostat == "Montana2"
                %20250409
                % dogSet(obj.handle_strainWatchdog, "Z_short_r", 1.783);
                % dogSet(obj.handle_strainWatchdog, "Z_short_theta", deg2rad(29.85));
                % dogSet(obj.handle_strainWatchdog, "Z_open_r", 27.9E6);
                % dogSet(obj.handle_strainWatchdog, "Z_open_theta", deg2rad(104.17));
                %20250904 new LCR meter
                dogSet(obj.handle_strainWatchdog, "Z_short_r", 2.402);
                dogSet(obj.handle_strainWatchdog, "Z_short_theta", deg2rad(41.89));
                dogSet(obj.handle_strainWatchdog, "Z_open_r", 20E9);
                dogSet(obj.handle_strainWatchdog, "Z_open_theta", deg2rad(65));
            end

            obj.address = address;
            obj.communicationHandle = handle;

            obj.addChannel("del_d", setTolerances = 5e-9);
            obj.addChannel("T", setTolerances = 0.1);
            obj.addChannel("Cp");
            obj.addChannel("Q");
            obj.addChannel("C");
            obj.addChannel("d");
            obj.addChannel("V_str_o", setTolerances = 5e-3);
            obj.addChannel("V_str_i", setTolerances = 5e-3);
            obj.addChannel("I_str_o");
            obj.addChannel("I_str_i");
            obj.addChannel("activeControl", setTolerances = 0.1);

            obj.setTimeout = hours(3);

            obj.rack_strainController = string(dogGet(obj.handle_strainWatchdog, "rack"));
        end

        function delete(obj)
            % Ask the watchdog to stop
            obj.stop();
        end

        function stop(obj)
            if ~isempty(obj.handle_strainWatchdog)
                try
                    dogSend(obj.handle_strainWatchdog, "STOP");
                    pause(5);
                catch
                end
                obj.handle_strainWatchdog = [];
            end
        end

        function tareData = tare(obj, d_0)
            arguments
                obj instrument_strainController;
                d_0 double {mustBeScalarOrEmpty} = [];
            end
            if isempty(d_0)
                dogSet(obj.handle_strainWatchdog, "tare", 20);
                tareData = dogGet(obj.handle_strainWatchdog, "tare");
            else
                dogSet(obj.handle_strainWatchdog, "d_0", d_0);
                tareData = [];
            end
        end

        function rack_strainController = getRack(obj)
            rack_strainController = obj.rack_strainController;
        end

        function plotLastSession(obj, options)
            % Plot the most recent watchdog session data saved by the worker.
            arguments
                obj instrument_strainController
                options.dataFolder (1,1) string = "dogTimetable";
                options.plotBranchNum (1,1) logical = true;
            end
            dataFolder = options.dataFolder;
            plotBranchNum = options.plotBranchNum;

            fileTable = struct2table(dir(dataFolder + filesep + "*.mat"));
            fileTable = sortrows(fileTable, "name", "descend");

            %% combine files
            if ~isempty(fileTable)
                fileCount = 1;
                if height(fileTable) == 1
                    firstFilename = fileTable.name;
                else
                    firstFilename = fileTable.name(1);
                end
                load(dataFolder + filesep + firstFilename);
                sessionTimetable = rmmissing(dataTimetable);
                for fileIndex = 2:height(fileTable)
                    load(dataFolder + filesep + fileTable.name(fileIndex));
                    if sessionTimetable.Time(1) - dataTimetable.Time(end) < minutes(5)
                        sessionTimetable = [dataTimetable; sessionTimetable]; %#ok<AGROW>
                        fileCount = fileCount + 1;
                    else
                        break;
                    end
                end
                disp("Loaded " + fileCount + " file(s).")
                %%
                if ~isempty(sessionTimetable)

                    f = figure();
                    if plotBranchNum
                        t = tiledlayout(f, 4, 1);
                    else
                        t = tiledlayout(f, 3, 1);
                    end

                    ax1 = nexttile(t);
                    hold(ax1, "on");
                    y_max = max(max(sessionTimetable.del_d_target * 1E6), max(sessionTimetable.del_d * 1E6));
                    y_min = min(min(sessionTimetable.del_d_target * 1E6), min(sessionTimetable.del_d * 1E6));
                    area(ax1, sessionTimetable.Time, (y_max - y_min + 0.15) * (abs(sessionTimetable.del_d - sessionTimetable.del_d_target) < 5E-9) + y_min - 0.075, y_min - 0.075, FaceColor = [0.9, 0.9, 0.9], EdgeColor = "none", ShowBaseLine = false, HandleVisibility = "off");
                    plot(ax1, sessionTimetable.Time, sessionTimetable.del_d_target * 1E6, "--k", LineWidth = 2);
                    plot(ax1, sessionTimetable.Time, sessionTimetable.del_d * 1E6, "b", LineWidth = 1);
                    ylim(ax1, [y_min - 0.1, y_max + 0.1])
                    ylabel("displacement [\mum]");
                    legend(["target", "measured"]);

                    ax2 = nexttile(t);
                    hold(ax2, "on");
                    plot(ax2, sessionTimetable.Time, sessionTimetable.V_str_o, "r", LineWidth = 1);
                    plot(ax2, sessionTimetable.Time, sessionTimetable.V_str_i, "b", LineWidth = 1);
                    [V_str_o_min, V_str_o_max, V_str_i_min, V_str_i_max] = obj.updateStrainVoltageBounds(sessionTimetable.T);
                    plot(ax2, sessionTimetable.Time, V_str_o_min, "--r", LineWidth = 1, HandleVisibility = "off");
                    plot(ax2, sessionTimetable.Time, V_str_o_max, "--r", LineWidth = 1, HandleVisibility = "off");
                    plot(ax2, sessionTimetable.Time, V_str_i_min, "--b", LineWidth = 1, HandleVisibility = "off");
                    plot(ax2, sessionTimetable.Time, V_str_i_max, "--b", LineWidth = 1, HandleVisibility = "off");
                    ylabel("strain voltage [V]");
                    legend(["outer", "inner"]);

                    ax3 = nexttile(t);
                    hold(ax3, "on");
                    plot(ax3, sessionTimetable.Time, sessionTimetable.T, "k", LineWidth = 1);
                    ylabel("temperature [K]");

                    if plotBranchNum
                        ax4 = nexttile(t);
                        hold(ax4, "on");
                        plot(ax4, sessionTimetable.Time, sessionTimetable.branchNum, "k", LineWidth = 1);
                        ylabel("branch []");

                        linkaxes([ax1, ax2, ax3, ax4], "x");
                    else
                        linkaxes([ax1, ax2, ax3], "x");
                    end
                else
                    warning("empty dataTimetable");
                end
            end

        end


    function [min, max] = strainVoltageBounds(~, T)

            min = nan(size(T));
            max = nan(size(T));

            range1 = T > 250;
            max(range1) = 120;
            min(range1) = -20;

            range2 = T <= 250 & T > 100;
            max(range2) = 120;
            min(range2) = -50 + (T(range2) - 100) / 5;

            range3 = T <= 100 & T > 10;
            max(range3) = 200 - (T(range3) - 10) * 8 / 9;
            min(range3) = -200 + (T(range3) - 10) * 5 / 3;

            range4 = T <= 10;
            max(range4) = 200;
            min(range4) = -200;

        end

        function [V_str_o_min, V_str_o_max, V_str_i_min, V_str_i_max] = updateStrainVoltageBounds(obj, T)
            temperatureSafeMargin = 3;
            voltageBoundFraction = 0.9;
            [V_min, V_max] = obj.strainVoltageBounds(T + temperatureSafeMargin);

            % outer voltages are connected so that positive corresponds to
            % stretch

            V_str_o_min = voltageBoundFraction * V_min;
            V_str_o_max = voltageBoundFraction * V_max;

            % inner voltages are connected so that negative corresponds to
            % stretch
            V_str_i_min = -V_str_o_max;
            V_str_i_max = -V_str_o_min;
        end
    end

    methods (Access = ?instrumentInterface)
        function getWriteChannelHelper(~, ~)
            % No-op: synchronous dogGet in getReadChannelHelper
        end

        function getValues = getReadChannelHelper(obj, channelIndex)
            channel = obj.channels(channelIndex);
            val = dogGet(obj.handle_strainWatchdog, channel, obj.dogGetTimeout);
            getValues = double(val);
        end

        function setWriteChannelHelper(obj, channelIndex, setValues)
            channel = obj.channels(channelIndex);
            switch channel
                case {"del_d", "T", "V_str_o", "V_str_i", "activeControl"}
                    dogSet(obj.handle_strainWatchdog, channel, setValues);
                otherwise
            end
        end

        function TF = setCheckChannelHelper(obj, channelIndex, ~)
            channel = obj.channels(channelIndex);
            switch channel
                case {"del_d", "T", "V_str_o", "V_str_i", "activeControl"}
                    TF = dogCheck(obj.handle_strainWatchdog, channel, obj.dogCheckTimeout);
                otherwise
            end
        end
    end
end
