function [accountEmails, userIds] = normalizeSlackNotificationRecipients(accountEmails, userIds)
%NORMALIZESLACKNOTIFICATIONRECIPIENTS Canonical email list and matching ID cache.
arguments
    accountEmails string
    userIds string = ""
end
if (~isempty(accountEmails) && ~isvector(accountEmails)) || any(ismissing(accountEmails), "all")
    error("sm:InvalidSlackRecipients", "Slack account emails must be a string vector without missing values.");
end
accountEmails = strip(split(join(accountEmails(:), ","), ",")).';
accountEmails = accountEmails(strlength(accountEmails) > 0);
[~, first] = unique(lower(accountEmails), "stable");
accountEmails = accountEmails(first);
if isempty(accountEmails)
    accountEmails = "";
end
if (~isempty(userIds) && ~isvector(userIds)) || any(ismissing(userIds), "all")
    error("sm:InvalidSlackRecipients", "Cached Slack user IDs must be a string vector without missing values.");
end
userIds = strip(userIds(:).');
if all(strlength(userIds) == 0)
    userIds = strings(size(accountEmails));
elseif numel(userIds) ~= numel(accountEmails)
    error("sm:InvalidSlackRecipients", "Cached Slack user IDs must match the normalized account email list.");
end
end
