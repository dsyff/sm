function smready(source, options)
%SMREADY Initialize measurement engine and launch SM GUIs.

arguments
    source (1, 1)
    options.singleThreaded (1, 1) logical = false
    options.verboseClient (1, 1) logical = false
    options.verboseWorker (1, 1) logical = false
    options.workerLogFile (1, 1) string = ""
    options.clientLogFile (1, 1) string = ""
    options.experimentRootPath {mustBeTextScalar} = ""
    options.slack_notification_settings (1, 1) struct = struct("webhook", "", "api_token", "", "channel_id", "", "account_email", "")
    options.slack_notification_webhook (1, 1) string = ""
end

global engine smscan smaux smdata bridge %#ok<GVMIS,NUSED>

slackSettings = struct("webhook", "", "api_token", "", "channel_id", "", "account_email", "");
inputSettings = options.slack_notification_settings;
if isfield(inputSettings, "webhook"), slackSettings.webhook = inputSettings.webhook; end
if isfield(inputSettings, "api_token"), slackSettings.api_token = inputSettings.api_token; end
if isfield(inputSettings, "channel_id"), slackSettings.channel_id = inputSettings.channel_id; end
if isfield(inputSettings, "account_email"), slackSettings.account_email = inputSettings.account_email; end

if evalin("base", "exist(""slack_notification_settings"", ""var"") == 1")
    baseSettings = evalin("base", "slack_notification_settings");
    if isstruct(baseSettings)
        if strlength(string(slackSettings.webhook)) == 0 && isfield(baseSettings, "webhook"), slackSettings.webhook = baseSettings.webhook; end
        if strlength(string(slackSettings.api_token)) == 0 && isfield(baseSettings, "api_token"), slackSettings.api_token = baseSettings.api_token; end
        if strlength(string(slackSettings.channel_id)) == 0 && isfield(baseSettings, "channel_id"), slackSettings.channel_id = baseSettings.channel_id; end
        if strlength(string(slackSettings.account_email)) == 0 && isfield(baseSettings, "account_email"), slackSettings.account_email = baseSettings.account_email; end
    end
end

if strlength(string(slackSettings.webhook)) == 0 && strlength(options.slack_notification_webhook) > 0
    slackSettings.webhook = options.slack_notification_webhook;
end
if strlength(string(slackSettings.webhook)) == 0 && evalin("base", "exist(""slack_notification_webhook"", ""var"") == 1")
    slackSettings.webhook = evalin("base", "slack_notification_webhook");
end

if isa(source, "instrumentRackRecipe") && strlength(string(slackSettings.account_email)) == 0
    slackSettings.account_email = source.slack_notification_account_email;
end

slackSettings.webhook = string(slackSettings.webhook);
slackSettings.api_token = string(slackSettings.api_token);
slackSettings.channel_id = string(slackSettings.channel_id);
slackSettings.account_email = string(slackSettings.account_email);
if ~isscalar(slackSettings.webhook), error("smready:InvalidSlackNotificationSettings", "slack_notification_settings.webhook must be a scalar string."); end
if ~isscalar(slackSettings.api_token), error("smready:InvalidSlackNotificationSettings", "slack_notification_settings.api_token must be a scalar string."); end
if ~isscalar(slackSettings.channel_id), error("smready:InvalidSlackNotificationSettings", "slack_notification_settings.channel_id must be a scalar string."); end
if ~isscalar(slackSettings.account_email), error("smready:InvalidSlackNotificationSettings", "slack_notification_settings.account_email must be a scalar string."); end

if ~(isa(source, "instrumentRack") || isa(source, "instrumentRackRecipe"))
    error("smready:InvalidInput", "smready expects instrumentRack or instrumentRackRecipe.");
end

if isa(source, "instrumentRack")
    engine = measurementEngine.fromRack(source, ...
        verboseClient = options.verboseClient, ...
        clientLogFile = options.clientLogFile, ...
        experimentRootPath = string(options.experimentRootPath), ...
        slack_notification_settings = slackSettings);
else
    engine = measurementEngine(source, ...
        singleThreaded = options.singleThreaded, ...
        verboseClient = options.verboseClient, ...
        verboseWorker = options.verboseWorker, ...
        workerLogFile = options.workerLogFile, ...
        clientLogFile = options.clientLogFile, ...
        experimentRootPath = string(options.experimentRootPath), ...
        slack_notification_settings = slackSettings);
end
engine.printRack();

bridge = smguiBridge(engine);
bridge.initializeSmdata();

smgui_small();
sm;
end
