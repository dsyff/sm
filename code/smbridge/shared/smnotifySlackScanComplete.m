function resolvedUserId = smnotifySlackScanComplete(scanName, imagePath, dataFilePath, scanDuration, slack_notification_settings)
    arguments
        scanName (1, 1) string
        imagePath (1, 1) string
        dataFilePath (1, 1) string = ""
        scanDuration (1, 1) duration = seconds(NaN)
        slack_notification_settings (1, 1) struct = struct("webhook", "", "api_token", "", "channel_id", "", "user_id", "", "account_email", "")
    end
    resolvedUserId = "";

    if strlength(strtrim(scanName)) == 0
        scanName = "scan";
    end
    if ~(isduration(scanDuration) && isfinite(seconds(scanDuration)) && scanDuration >= seconds(0))
        warning("sm:MissingScanDuration", ...
            "Slack image notification skipped: missing measured scan duration for scan %s", scanName);
        return;
    end
    if ~isfile(imagePath)
        warning("sm:MissingScanImage", ...
            "Slack image notification skipped: image file not found %s", imagePath);
        return;
    end
    if strlength(dataFilePath) == 0 || ~isfile(dataFilePath)
        warning("sm:MissingScanDataFile", ...
            "Slack image notification skipped: scan data file not found %s", dataFilePath);
        return;
    end

    totalSeconds = floor(seconds(scanDuration));
    hoursPart = floor(totalSeconds / 3600);
    minutesPart = floor(mod(totalSeconds, 3600) / 60);
    secondsPart = mod(totalSeconds, 60);
    durationParts = strings(0, 1);
    if hoursPart > 0
        durationParts(end+1) = hoursPart + " hours";
    end
    if minutesPart > 0
        durationParts(end+1) = minutesPart + " minutes";
    end
    durationParts(end+1) = secondsPart + " seconds";
    durationText = strjoin(durationParts, " ");
    [~, imageName, imageExt] = fileparts(imagePath);
    imageFilename = imageName + imageExt;
    [~, dataName, dataExt] = fileparts(dataFilePath);
    dataFilename = dataName + dataExt;
    messageText = "Scan """ + scanName + """ from your queue has completed. The scan took " + durationText + ". Saved data file: " + dataFilename + ".";

    token = "";
    if isfield(slack_notification_settings, "api_token")
        token = string(slack_notification_settings.api_token);
    end
    token = strip(token);
    if strlength(token) == 0
        warning("sm:MissingSlackApiToken", ...
            "Slack image notification skipped: slack_notification_settings.api_token is empty.");
        return;
    end

    cachedUserId = "";
    if isfield(slack_notification_settings, "user_id")
        cachedUserId = string(slack_notification_settings.user_id);
    end
    cachedUserId = strip(cachedUserId);
    if ~isscalar(cachedUserId)
        warning("sm:InvalidSlackNotificationSettings", ...
            "Slack image notification skipped: cached Slack recipient id must be a scalar string.");
        return;
    end

    accountEmail = "";
    if isfield(slack_notification_settings, "account_email")
        accountEmail = string(slack_notification_settings.account_email);
    elseif isfield(slack_notification_settings, "slack_notification_account_email")
        accountEmail = string(slack_notification_settings.slack_notification_account_email);
    end
    accountEmail = strip(accountEmail);
    if ~isscalar(accountEmail)
        warning("sm:InvalidSlackNotificationSettings", ...
            "Slack image notification skipped: slack_notification_settings.account_email must be a scalar string.");
        return;
    end

    channelId = "";
    if isfield(slack_notification_settings, "channel_id")
        channelId = string(slack_notification_settings.channel_id);
    elseif isfield(slack_notification_settings, "channelId")
        channelId = string(slack_notification_settings.channelId);
    end
    channelId = strip(channelId);
    if ~isscalar(channelId)
        warning("sm:InvalidSlackNotificationSettings", ...
            "Slack image notification skipped: slack_notification_settings.channel_id must be a scalar string.");
        return;
    end

    authValue = "Bearer " + token;
    headerFields = {char("Authorization"), char(authValue)};
    optsForm = weboptions( ...
        RequestMethod = "post", ...
        MediaType = "application/x-www-form-urlencoded", ...
        HeaderFields = headerFields, ...
        Timeout = 30);

    targetChannelId = channelId;
    if strlength(accountEmail) > 0
        userId = cachedUserId;
        if strlength(userId) == 0
            encodedEmail = char(java.net.URLEncoder.encode(char(accountEmail), "UTF-8"));
            lookupUrl = "https://slack.com/api/users.lookupByEmail?email=" + string(encodedEmail);
            optsGet = weboptions( ...
                RequestMethod = "get", ...
                HeaderFields = headerFields, ...
                Timeout = 30);
            try
                lookupResp = webread(lookupUrl, optsGet);
            catch ME
                warning("sm:SlackUserLookupFailed", "Slack image notification skipped: users.lookupByEmail failed (%s).", ME.message);
                return;
            end
            if ~(isstruct(lookupResp) && isfield(lookupResp, "ok") && logical(lookupResp.ok))
                errText = "unknown";
                if isstruct(lookupResp) && isfield(lookupResp, "error")
                    errText = string(lookupResp.error);
                end
                warning("sm:SlackUserLookupFailed", ...
                    "Slack image notification skipped: users.lookupByEmail returned not-ok for account_email %s (%s).", ...
                    accountEmail, errText);
                return;
            end
            if ~isfield(lookupResp, "user") || ~isfield(lookupResp.user, "id")
                warning("sm:SlackUserLookupFailed", "Slack image notification skipped: users.lookupByEmail missing user id.");
                return;
            end
            userId = string(lookupResp.user.id);
        end
        resolvedUserId = userId;
        try
            openResp = webwrite("https://slack.com/api/conversations.open", ...
                "users", char(userId), optsForm);
        catch ME
            warning("sm:SlackDmOpenFailed", "Slack image notification skipped: conversations.open failed (%s).", ME.message);
            return;
        end
        if ~(isstruct(openResp) && isfield(openResp, "ok") && logical(openResp.ok))
            warning("sm:SlackDmOpenFailed", "Slack image notification skipped: conversations.open returned not-ok.");
            return;
        end
        if ~isfield(openResp, "channel") || ~isfield(openResp.channel, "id")
            warning("sm:SlackDmOpenFailed", "Slack image notification skipped: conversations.open missing channel id.");
            return;
        end
        targetChannelId = string(openResp.channel.id);
    end

    if strlength(targetChannelId) == 0
        warning("sm:MissingSlackChannelId", ...
            "Slack image notification skipped: set slack_notification_settings.channel_id for default channel sends.");
        return;
    end

    try
        uploadPaths = [imagePath; dataFilePath];
        uploadFilenames = [imageFilename; dataFilename];
        for k = 1:numel(uploadPaths)
            currentPath = uploadPaths(k);
            uploadFilename = uploadFilenames(k);
            fid = fopen(currentPath, "rb");
            if fid < 0
                warning("sm:UploadFileOpenFailed", "Slack image notification skipped: cannot open file %s", currentPath);
                return;
            end
            fileCloser = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fileBytes = fread(fid, Inf, "*uint8");
            fileLen = numel(fileBytes);
            if fileLen == 0
                warning("sm:EmptyUploadFile", "Slack image notification skipped: upload file is empty %s", currentPath);
                return;
            end

            r1 = webwrite("https://slack.com/api/files.getUploadURLExternal", ...
                "filename", char(uploadFilename), ...
                "length", char(string(fileLen)), ...
                optsForm);
            if ~(isstruct(r1) && isfield(r1, "ok") && logical(r1.ok))
                warning("sm:SlackUploadInitFailed", "Slack image notification skipped: files.getUploadURLExternal returned not-ok.");
                return;
            end
            if ~isfield(r1, "upload_url") || ~isfield(r1, "file_id")
                warning("sm:SlackUploadInitFailed", "Slack image notification skipped: upload url or file id missing.");
                return;
            end
            uploadUrl = string(r1.upload_url);
            fileId = string(r1.file_id);

            req2 = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.POST, ...
                matlab.net.http.HeaderField("Content-Type", "application/octet-stream"), ...
                uint8(fileBytes));
            resp2 = req2.send(matlab.net.URI(char(uploadUrl)));
            if double(resp2.StatusCode) < 200 || double(resp2.StatusCode) >= 300
                warning("sm:SlackUploadPutFailed", ...
                    "Slack image notification skipped: upload to pre-signed URL failed with HTTP %d.", double(resp2.StatusCode));
                return;
            end

            fileObj = struct("id", char(fileId), "title", char(uploadFilename));
            filesJsonArray = "[" + string(jsonencode(fileObj)) + "]";
            r3 = webwrite("https://slack.com/api/files.completeUploadExternal", ...
                "files", char(filesJsonArray), ...
                "channel_id", char(targetChannelId), ...
                "initial_comment", "", ...
                optsForm);
            if ~(isstruct(r3) && isfield(r3, "ok") && logical(r3.ok))
                errText = "unknown";
                if isstruct(r3) && isfield(r3, "error")
                    errText = string(r3.error);
                end
                warning("sm:SlackUploadCompleteFailed", "Slack image notification skipped: files.completeUploadExternal returned not-ok (%s).", errText);
                return;
            end
        end

        r4 = webwrite("https://slack.com/api/chat.postMessage", ...
            "channel", char(targetChannelId), ...
            "text", char(messageText), ...
            optsForm);
        if ~(isstruct(r4) && isfield(r4, "ok") && logical(r4.ok))
            errText = "unknown";
            if isstruct(r4) && isfield(r4, "error")
                errText = string(r4.error);
            end
            warning("sm:SlackPostMessageFailed", "Slack image notification sent files but message post failed (%s).", errText);
            return;
        end
    catch ME
        warning("sm:SlackNotificationFailed", "Slack image notification skipped: %s", ME.message);
        return;
    end
end
