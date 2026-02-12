classdef experimentContext
    % experimentContext - Shared experiment context for SM 1.5.
    %
    % This class stores the experimentRootPath in-process (client or worker).
    % Only measurementEngine is allowed to set it; all other code can read it.

    methods (Static)
        function rootPath = getExperimentRootPath()
            rootPath = experimentContext.rootStore_();
        end

        function nChars = print(varargin)
            if nargin < 1
                error("experimentContext:PrintInvalidUsage", "print requires a message or format string.");
            end

            if isnumeric(varargin{1}) && isscalar(varargin{1})
                fileId = double(varargin{1});
                if nargin < 2
                    error("experimentContext:PrintInvalidUsage", "print(fileId, ...) requires a format string.");
                end
                if isempty(getCurrentWorker())
                    nChars = fprintf(fileId, varargin{2:end});
                    return;
                end
                if fileId ~= 1 && fileId ~= 2
                    nChars = fprintf(fileId, varargin{2:end});
                    return;
                end
                message = string(sprintf(varargin{2:end}));
                experimentContext.relayWorkerFprintf(message);
                nChars = double(strlength(message));
                return;
            elseif nargin == 1
                value = varargin{1};
                if isstring(value) && isscalar(value)
                    message = value;
                elseif ischar(value)
                    message = string(value);
                else
                    lines = splitlines(string(evalc("disp(value)")));
                    if numel(lines) > 1 && strlength(lines(end)) == 0
                        lines = lines(1:end-1);
                    end
                    message = strjoin(lines, newline);
                end
            else
                message = string(sprintf(varargin{:}));
            end

            if isempty(getCurrentWorker())
                experimentContext.emitLocalMessage_(message);
                nChars = double(strlength(message));
                return;
            end

            experimentContext.relayWorkerFprintf(message);
            nChars = double(strlength(message));
        end

        function tf = relayWorkerFprintf(message)
            arguments
                message {mustBeTextScalar}
            end

            worker = getCurrentWorker();
            if isempty(worker)
                error("experimentContext:NotOnWorker", "relayWorkerFprintf must be called on a worker.");
            end
            [dataQueue, header] = experimentContext.fprintfRelayStore_();
            if isempty(dataQueue) || ~isa(dataQueue, "parallel.pool.DataQueue")
                error("experimentContext:MissingFprintfQueue", "Worker fprintf relay queue is not configured.");
            end
            if strlength(header) == 0
                header = "worker";
            end

            payload = struct("header", header, "message", string(message));
            send(dataQueue, payload);
            tf = true;
        end
    end

    methods (Static, Access = ?measurementEngine)
        function setExperimentRootPath(rootPath)
            arguments
                rootPath {mustBeTextScalar}
            end
            experimentContext.rootStore_(string(rootPath));
        end

        function setFprintfRelay(dataQueue, header)
            arguments
                dataQueue
                header {mustBeTextScalar} = ""
            end

            if isempty(dataQueue) || ~isa(dataQueue, "parallel.pool.DataQueue")
                error("experimentContext:InvalidDataQueue", "setFprintfRelay expects a non-empty parallel.pool.DataQueue.");
            end

            experimentContext.fprintfRelayStore_(dataQueue, string(header));
        end
    end

    methods (Static, Access = private)
        function emitLocalMessage_(message)
            lines = splitlines(string(message));
            if numel(lines) > 1 && strlength(lines(end)) == 0
                lines = lines(1:end-1);
            end
            if isempty(lines)
                fprintf("\n");
                return;
            end
            for i = 1:numel(lines)
                fprintf("%s\n", char(lines(i)));
            end
        end

        function rootPath = rootStore_(newValue)
            persistent stored
            if isempty(stored)
                stored = "";
            end

            if nargin >= 1
                stored = string(newValue);
                if strlength(stored) > 0
                    setenv("SM_EXPERIMENT_ROOT", char(stored));
                end
            elseif strlength(stored) == 0
                env = string(getenv("SM_EXPERIMENT_ROOT"));
                if strlength(env) > 0
                    stored = env;
                end
            end

            rootPath = stored;
        end

        function [dataQueue, header] = fprintfRelayStore_(newQueue, newHeader)
            persistent storedQueue storedHeader
            if isempty(storedHeader)
                storedHeader = "";
            end

            if nargin >= 1
                storedQueue = newQueue;
            end
            if nargin >= 2
                storedHeader = string(newHeader);
            end

            if isempty(storedQueue)
                dataQueue = [];
            else
                dataQueue = storedQueue;
            end
            header = storedHeader;
        end
    end
end

