classdef smQueueState < handle
    %SMQUEUESTATE GUI-independent state owner for the scan library and queue.
    %
    % The singleton is stored in global smaux.queueState. Public operations
    % reconcile direct changes to smaux.scans/smq before reading or mutating
    % state. Queue phases are idle, runningScan, runningRaw, betweenItems,
    % stoppingAfterCurrent, stoppingNow, and finalizing.

    properties (Access = private)
        scanIds = strings(1, 0)
        queueIds = strings(1, 0)
        scanMirror = cell(1, 0)
        queueMirror = cell(1, 0)
        selectedScanId (1, 1) string = ""
        selectedQueueId (1, 1) string = ""
        rawDraft (1, 1) string = ""
        activeSource (1, 1) string = "scans"
        queuePhase (1, 1) string = "idle"
        runningItem = []
        stopAfterCurrent (1, 1) logical = false
        stopNowRequested (1, 1) logical = false
        attachedView = []
        nextIdentity (1, 1) uint64 = uint64(1)
        initialized (1, 1) logical = false
    end

    methods (Static)
        function obj = get()
            global smaux %#ok<GVMIS>
            if isempty(smaux)
                smaux = struct();
            elseif ~isstruct(smaux)
                error("smQueueState:InvalidSmaux", "Global smaux must be a struct.");
            end
            if ~isfield(smaux, "queueState") || ~isa(smaux.queueState, "smQueueState") ...
                    || ~isvalid(smaux.queueState)
                smaux.queueState = smQueueState();
            end
            obj = smaux.queueState;
            obj.reconcileCompatibility();
        end
    end

    methods
        function state = snapshot(obj)
            obj.reconcileCompatibility();
            global smaux %#ok<GVMIS>
            viewHandle = obj.validView();
            state = struct( ...
                "scans", {smaux.scans}, ...
                "scanIds", obj.scanIds, ...
                "queue", {smaux.smq}, ...
                "queueIds", obj.queueIds, ...
                "selectedScanId", obj.selectedScanId, ...
                "selectedScanIndex", obj.indexOf(obj.scanIds, obj.selectedScanId), ...
                "selectedQueueId", obj.selectedQueueId, ...
                "selectedQueueIndex", obj.indexOf(obj.queueIds, obj.selectedQueueId), ...
                "draft", obj.rawDraft, ...
                "source", obj.activeSource, ...
                "queuePhase", obj.queuePhase, ...
                "runningItem", obj.runningItem, ...
                "stopAfterCurrent", obj.stopAfterCurrent, ...
                "stopNowRequested", obj.stopNowRequested, ...
                "view", viewHandle, ...
                "hasView", ~isempty(viewHandle));
        end

        function attachView(obj, viewHandle)
            obj.reconcileCompatibility();
            if ~isscalar(viewHandle) || ~isgraphics(viewHandle, "figure")
                error("smQueueState:InvalidView", "Queue view must be a valid scalar figure.");
            end
            current = obj.validView();
            if ~isempty(current) && current ~= viewHandle
                error("smQueueState:ViewAlreadyAttached", "A queue view is already attached.");
            end
            obj.attachedView = viewHandle;
        end

        function detached = detachView(obj, viewHandle)
            obj.reconcileCompatibility();
            current = obj.validView();
            if nargin < 2
                viewHandle = current;
            end
            detached = ~isempty(current) && isequal(current, viewHandle);
            if detached
                obj.attachedView = [];
            end
        end

        function viewHandle = view(obj)
            obj.reconcileCompatibility();
            viewHandle = obj.validView();
        end

        function setDraft(obj, value)
            obj.reconcileCompatibility();
            obj.rawDraft = obj.textScalar(value);
        end

        function setSource(obj, source)
            obj.reconcileCompatibility();
            source = string(source);
            if ~isscalar(source) || ~ismember(source, ["scans", "raw"])
                error("smQueueState:InvalidSource", "Source must be scans or raw.");
            end
            obj.activeSource = source;
        end

        function selectedId = select(obj, kind, indexOrId)
            obj.reconcileCompatibility();
            kind = obj.selectionKind(kind);
            if kind == "scans"
                obj.selectedScanId = obj.resolveSelection(obj.scanIds, indexOrId);
                obj.activeSource = "scans";
                selectedId = obj.selectedScanId;
            else
                obj.selectedQueueId = obj.resolveSelection(obj.queueIds, indexOrId);
                selectedId = obj.selectedQueueId;
            end
        end

        function [found, entry] = selected(obj, kind)
            obj.reconcileCompatibility();
            kind = obj.selectionKind(kind);
            global smaux %#ok<GVMIS>
            if kind == "scans"
                values = smaux.scans;
                ids = obj.scanIds;
                id = obj.selectedScanId;
            else
                values = smaux.smq;
                ids = obj.queueIds;
                id = obj.selectedQueueId;
            end
            index = obj.indexOf(ids, id);
            found = ~isempty(index);
            if found
                entry = obj.makeItem(ids(index), values{index}, index);
            else
                entry = [];
            end
        end

        function ids = appendScans(obj, values, selectFirst)
            obj.reconcileCompatibility();
            if nargin < 3
                selectFirst = true;
            end
            values = obj.payloadCells(values);
            ids = obj.newIds("scan", numel(values));
            if isempty(values)
                return;
            end
            global smaux %#ok<GVMIS>
            first = numel(smaux.scans) + 1;
            obj.commitScans([smaux.scans values], [obj.scanIds ids]);
            if selectFirst
                obj.selectedScanId = obj.scanIds(first);
            end
        end

        function ids = appendPending(obj, values, selectFirst)
            obj.reconcileCompatibility();
            if nargin < 3
                selectFirst = true;
            end
            values = obj.payloadCells(values);
            ids = obj.newIds("queue", numel(values));
            if isempty(values)
                return;
            end
            global smaux %#ok<GVMIS>
            first = numel(smaux.smq) + 1;
            obj.commitQueue([smaux.smq values], [obj.queueIds ids]);
            if selectFirst
                obj.selectedQueueId = obj.queueIds(first);
            end
        end

        function [inserted, newId] = insert(obj, where)
            obj.reconcileCompatibility();
            where = string(where);
            if ~isscalar(where) || ~ismember(where, ["top", "after", "end"])
                error("smQueueState:InvalidInsertion", "Insertion must be top, after, or end.");
            end
            global smaux %#ok<GVMIS>
            if obj.activeSource == "scans"
                sourceIndex = obj.indexOf(obj.scanIds, obj.selectedScanId);
                if isempty(sourceIndex)
                    inserted = false;
                    newId = "";
                    return;
                end
                payload = smaux.scans{sourceIndex};
            else
                if strlength(strip(obj.rawDraft)) == 0
                    inserted = false;
                    newId = "";
                    return;
                end
                payload = struct("eval", obj.rawDraft);
            end

            count = numel(smaux.smq);
            if count == 0
                insertAt = 1;
            elseif where == "top"
                insertAt = 1;
            elseif where == "end"
                insertAt = count + 1;
            else
                selectedIndex = obj.indexOf(obj.queueIds, obj.selectedQueueId);
                if isempty(selectedIndex)
                    inserted = false;
                    newId = "";
                    return;
                end
                insertAt = selectedIndex + 1;
            end

            newId = obj.newIds("queue", 1);
            values = [smaux.smq(1:insertAt-1) {payload} smaux.smq(insertAt:end)];
            ids = [obj.queueIds(1:insertAt-1) newId obj.queueIds(insertAt:end)];
            obj.commitQueue(values, ids);
            obj.selectedQueueId = newId;
            if obj.activeSource == "raw"
                obj.rawDraft = "";
            end
            inserted = true;
        end

        function moved = move(obj, direction)
            obj.reconcileCompatibility();
            direction = string(direction);
            if ~isscalar(direction) || ~ismember(direction, ["up", "down"])
                error("smQueueState:InvalidMove", "Move direction must be up or down.");
            end
            index = obj.indexOf(obj.queueIds, obj.selectedQueueId);
            if isempty(index)
                moved = false;
                return;
            end
            target = index + (direction == "down") - (direction == "up");
            if target < 1 || target > numel(obj.queueIds)
                moved = false;
                return;
            end
            global smaux %#ok<GVMIS>
            values = smaux.smq;
            ids = obj.queueIds;
            values([index target]) = values([target index]);
            ids([index target]) = ids([target index]);
            obj.commitQueue(values, ids);
            moved = true;
        end

        function [removed, entry] = remove(obj, kind)
            obj.reconcileCompatibility();
            kind = obj.selectionKind(kind);
            global smaux %#ok<GVMIS>
            if kind == "scans"
                index = obj.indexOf(obj.scanIds, obj.selectedScanId);
                if isempty(index)
                    removed = false;
                    entry = [];
                    return;
                end
                entry = obj.makeItem(obj.scanIds(index), smaux.scans{index}, index);
                values = smaux.scans;
                ids = obj.scanIds;
                values(index) = [];
                ids(index) = [];
                obj.commitScans(values, ids);
                obj.selectedScanId = obj.nearestId(ids, index);
            else
                index = obj.indexOf(obj.queueIds, obj.selectedQueueId);
                if isempty(index)
                    removed = false;
                    entry = [];
                    return;
                end
                entry = obj.makeItem(obj.queueIds(index), smaux.smq{index}, index);
                values = smaux.smq;
                ids = obj.queueIds;
                values(index) = [];
                ids(index) = [];
                obj.commitQueue(values, ids);
                obj.selectedQueueId = obj.nearestId(ids, index);
            end
            removed = true;
        end

        function [edited, entry] = editQueued(obj)
            obj.reconcileCompatibility();
            global smaux %#ok<GVMIS>
            index = obj.indexOf(obj.queueIds, obj.selectedQueueId);
            if isempty(index)
                edited = false;
                entry = [];
                return;
            end
            entry = obj.makeItem(obj.queueIds(index), smaux.smq{index}, index);
            if entry.kind == "raw"
                obj.rawDraft = obj.rawText(entry.payload);
                obj.activeSource = "raw";
                values = smaux.smq;
                ids = obj.queueIds;
                values(index) = [];
                ids(index) = [];
                obj.commitQueue(values, ids);
                obj.selectedQueueId = obj.nearestId(ids, index);
            end
            edited = true;
        end

        function begun = beginRun(obj)
            obj.reconcileCompatibility();
            global smaux %#ok<GVMIS>
            begun = obj.queuePhase == "idle" && isempty(obj.runningItem) && ~isempty(smaux.smq);
            if begun
                obj.stopAfterCurrent = false;
                obj.stopNowRequested = false;
                obj.queuePhase = "betweenItems";
            end
        end

        function [started, item] = startNext(obj)
            obj.reconcileCompatibility();
            if obj.queuePhase ~= "betweenItems" || ~isempty(obj.runningItem)
                started = false;
                item = [];
                return;
            end
            if obj.stopAfterCurrent || obj.stopNowRequested
                obj.setIdle();
                started = false;
                item = [];
                return;
            end
            [started, item] = obj.beginNext();
        end

        function shouldContinue = finishCurrent(obj, outcome)
            obj.reconcileCompatibility();
            outcome = string(outcome);
            if ~isscalar(outcome) || ~ismember(outcome, ["complete", "stopped", "error"])
                error("smQueueState:InvalidOutcome", "Outcome must be complete, stopped, or error.");
            end
            if isempty(obj.runningItem)
                shouldContinue = false;
                return;
            end
            global smaux %#ok<GVMIS>
            shouldContinue = outcome == "complete" && ~obj.stopAfterCurrent ...
                && ~obj.stopNowRequested && ~isempty(smaux.smq);
            obj.runningItem = [];
            if shouldContinue
                obj.queuePhase = "betweenItems";
            else
                obj.setIdle();
            end
        end

        function endRun(obj)
            obj.reconcileCompatibility();
            obj.setIdle();
        end

        function accepted = requestStopAfter(obj)
            obj.reconcileCompatibility();
            accepted = ismember(obj.queuePhase, ["runningScan", "runningRaw", ...
                "betweenItems", "stoppingAfterCurrent", "finalizing"]);
            if ~accepted
                return;
            end
            obj.stopAfterCurrent = true;
            if ismember(obj.queuePhase, ["runningScan", "runningRaw"])
                obj.queuePhase = "stoppingAfterCurrent";
            end
        end

        function action = requestStopNow(obj)
            obj.reconcileCompatibility();
            if ismember(obj.queuePhase, ["finalizing", "betweenItems"])
                obj.stopAfterCurrent = true;
                action = "stopAfter";
            elseif obj.queuePhase == "runningScan" || ...
                    (obj.queuePhase == "stoppingAfterCurrent" && ...
                    ~isempty(obj.runningItem) && obj.runningItem.kind == "scan")
                obj.stopAfterCurrent = false;
                obj.stopNowRequested = true;
                obj.queuePhase = "stoppingNow";
                action = "stopNow";
            else
                action = "";
            end
        end

        function changed = setFinalizing(obj)
            obj.reconcileCompatibility();
            changed = ~isempty(obj.runningItem) && obj.runningItem.kind == "scan" ...
                && ismember(obj.queuePhase, ["runningScan", "stoppingAfterCurrent", "stoppingNow"]);
            if changed
                obj.queuePhase = "finalizing";
            end
        end
    end

    methods (Access = private)
        function obj = smQueueState()
            obj.reconcileCompatibility();
        end

        function reconcileCompatibility(obj)
            global smaux %#ok<GVMIS>
            if isempty(smaux)
                smaux = struct();
            elseif ~isstruct(smaux)
                error("smQueueState:InvalidSmaux", "Global smaux must be a struct.");
            end
            if ~isfield(smaux, "scans")
                smaux.scans = {};
            elseif ~iscell(smaux.scans)
                error("smQueueState:InvalidScans", "smaux.scans must be a cell array.");
            end
            if ~isfield(smaux, "smq")
                smaux.smq = {};
            elseif ~iscell(smaux.smq)
                error("smQueueState:InvalidQueue", "smaux.smq must be a cell array.");
            end
            smaux.scans = reshape(smaux.scans, 1, []);
            smaux.smq = reshape(smaux.smq, 1, []);

            oldScanIndex = obj.indexOf(obj.scanIds, obj.selectedScanId);
            oldQueueIndex = obj.indexOf(obj.queueIds, obj.selectedQueueId);
            obj.scanIds = obj.reconcileIds(obj.scanMirror, obj.scanIds, smaux.scans, "scan");
            obj.queueIds = obj.reconcileIds(obj.queueMirror, obj.queueIds, smaux.smq, "queue");
            obj.scanMirror = smaux.scans;
            obj.queueMirror = smaux.smq;

            obj.selectedScanId = obj.reconcileSelection(obj.selectedScanId, oldScanIndex, obj.scanIds);
            obj.selectedQueueId = obj.reconcileSelection(obj.selectedQueueId, oldQueueIndex, obj.queueIds);
            if ~obj.initialized
                if obj.selectedScanId == "" && ~isempty(obj.scanIds)
                    obj.selectedScanId = obj.scanIds(1);
                end
                if obj.selectedQueueId == "" && ~isempty(obj.queueIds)
                    obj.selectedQueueId = obj.queueIds(1);
                end
                obj.initialized = true;
            end
            obj.validView();
        end

        function ids = reconcileIds(obj, oldValues, oldIds, newValues, prefix)
            if isequaln(oldValues, newValues)
                ids = oldIds;
                return;
            end
            ids = strings(1, numel(newValues));
            used = false(1, numel(oldValues));
            for newIndex = 1:numel(newValues)
                match = [];
                for oldIndex = 1:numel(oldValues)
                    if ~used(oldIndex) && isequaln(newValues{newIndex}, oldValues{oldIndex})
                        match = oldIndex;
                        break;
                    end
                end
                if isempty(match)
                    ids(newIndex) = obj.newIds(prefix, 1);
                else
                    used(match) = true;
                    ids(newIndex) = oldIds(match);
                end
            end
        end

        function ids = newIds(obj, prefix, count)
            ids = strings(1, count);
            for index = 1:count
                ids(index) = prefix + "-" + string(obj.nextIdentity);
                obj.nextIdentity = obj.nextIdentity + 1;
            end
        end

        function commitScans(obj, values, ids)
            global smaux %#ok<GVMIS>
            smaux.scans = reshape(values, 1, []);
            obj.scanMirror = smaux.scans;
            obj.scanIds = reshape(ids, 1, []);
        end

        function commitQueue(obj, values, ids)
            global smaux %#ok<GVMIS>
            smaux.smq = reshape(values, 1, []);
            obj.queueMirror = smaux.smq;
            obj.queueIds = reshape(ids, 1, []);
        end

        function [started, item] = beginNext(obj)
            global smaux %#ok<GVMIS>
            if isempty(smaux.smq)
                obj.setIdle();
                started = false;
                item = [];
                return;
            end
            id = obj.queueIds(1);
            payload = smaux.smq{1};
            values = smaux.smq;
            ids = obj.queueIds;
            values(1) = [];
            ids(1) = [];
            obj.commitQueue(values, ids);
            if obj.selectedQueueId == id
                obj.selectedQueueId = obj.nearestId(ids, 1);
            end
            item = obj.makeItem(id, payload, 1);
            obj.runningItem = item;
            obj.stopAfterCurrent = false;
            obj.stopNowRequested = false;
            if item.kind == "raw"
                obj.queuePhase = "runningRaw";
            else
                obj.queuePhase = "runningScan";
            end
            started = true;
        end

        function setIdle(obj)
            obj.queuePhase = "idle";
            obj.runningItem = [];
            obj.stopAfterCurrent = false;
            obj.stopNowRequested = false;
        end

        function item = makeItem(obj, id, payload, index)
            kind = obj.itemKind(payload);
            item = struct("id", id, "payload", payload, "kind", kind, ...
                "label", obj.itemLabel(payload, kind), "index", index);
        end

        function kind = itemKind(~, payload)
            if isstruct(payload) && isscalar(payload) && isfield(payload, "eval") ...
                    && ~isfield(payload, "loops")
                kind = "raw";
            else
                kind = "scan";
            end
        end

        function label = itemLabel(obj, payload, kind)
            if kind == "raw"
                lines = splitlines(obj.rawText(payload));
                lines = lines(strlength(strip(lines)) > 0);
                if isempty(lines)
                    label = "[CMD]";
                else
                    label = "[CMD] " + lines(1);
                end
            elseif isstruct(payload) && isfield(payload, "name")
                label = string(payload.name);
            elseif isobject(payload) && isprop(payload, "name")
                label = string(payload.name);
            else
                label = "Scan";
            end
            if ~isscalar(label)
                label = join(label(:), " ");
            end
        end

        function text = rawText(obj, payload)
            text = obj.textScalar(payload.eval);
        end

        function text = textScalar(~, value)
            if ischar(value)
                if isempty(value)
                    text = "";
                elseif isrow(value)
                    text = string(value);
                else
                    text = join(string(cellstr(value)), newline);
                end
            elseif isstring(value) || iscellstr(value)
                text = join(string(value(:)), newline);
            else
                error("smQueueState:InvalidText", "Raw command text must be char, string, or cellstr.");
            end
        end

        function cells = payloadCells(~, values)
            if iscell(values)
                cells = reshape(values, 1, []);
            elseif isstruct(values)
                cells = reshape(num2cell(values), 1, []);
            else
                error("smQueueState:InvalidPayload", "Payloads must be a struct array or cell array.");
            end
        end

        function kind = selectionKind(~, kind)
            kind = string(kind);
            if ~isscalar(kind) || ~ismember(kind, ["scans", "queue"])
                error("smQueueState:InvalidSelectionKind", "Selection kind must be scans or queue.");
            end
        end

        function id = resolveSelection(~, ids, indexOrId)
            if isempty(indexOrId)
                id = "";
            elseif isnumeric(indexOrId)
                if isscalar(indexOrId) && isfinite(indexOrId) && indexOrId == fix(indexOrId) ...
                        && indexOrId >= 1 && indexOrId <= numel(ids)
                    id = ids(indexOrId);
                else
                    id = "";
                end
            elseif ischar(indexOrId) || isstring(indexOrId)
                candidate = string(indexOrId);
                if isscalar(candidate) && any(ids == candidate)
                    id = candidate;
                else
                    id = "";
                end
            else
                error("smQueueState:InvalidSelection", "Selection must be an index or identity.");
            end
        end

        function id = reconcileSelection(obj, id, oldIndex, newIds)
            if id ~= "" && any(newIds == id)
                return;
            end
            if id ~= "" && ~isempty(oldIndex)
                id = obj.nearestId(newIds, oldIndex);
            else
                id = "";
            end
        end

        function id = nearestId(~, ids, index)
            if isempty(ids)
                id = "";
            else
                id = ids(min(index, numel(ids)));
            end
        end

        function index = indexOf(~, ids, id)
            if id == ""
                index = [];
            else
                index = find(ids == id, 1);
            end
        end

        function viewHandle = validView(obj)
            if isempty(obj.attachedView) || ~isscalar(obj.attachedView) ...
                    || ~isgraphics(obj.attachedView, "figure")
                obj.attachedView = [];
            end
            viewHandle = obj.attachedView;
        end
    end
end
