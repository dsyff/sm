classdef attodryDisplacementFit
    methods (Static)
        function model = buildModel(referenceImage, options)
            arguments
                referenceImage {mustBeNumeric, mustBeNonempty}
                options (1, 1) struct = struct()
            end
            if any(~isfinite(double(referenceImage(:))))
                error("attodryDisplacementFit:InvalidReferenceImage", ...
                    "Reference image contains non-finite values.");
            end
            options = attodryDisplacementFit.withDefaultOptions(options);
            if options.sampleOffsetEstimatorMode ~= "spline_shift"
                error("attodryDisplacementFit:UnknownEstimator", ...
                    "sampleOffsetEstimatorMode must be ""spline_shift"".");
            end
            referenceFiltered = log(double(referenceImage) + 1);
            [rows, cols] = size(referenceFiltered);
            [fitRows, fitCols, xTrim, yTrim, sampleRows, sampleCols] = ...
                attodryDisplacementFit.sampleIndices([rows, cols], options.offsetFitRoi_px, ...
                options.shiftFitTrimRatio, options.minimumOffsetFitRoiSize_px);
            model = struct( ...
                "referenceFiltered", referenceFiltered, ...
                "imageSize", [rows, cols], ...
                "fitRows", fitRows, ...
                "fitCols", fitCols, ...
                "sampleRows", sampleRows, ...
                "sampleCols", sampleCols, ...
                "xTrim", xTrim, ...
                "yTrim", yTrim, ...
                "sampleOffsetEstimatorMode", options.sampleOffsetEstimatorMode, ...
                "offsetFitDownsampleFactor", options.offsetFitDownsampleFactor, ...
                "offsetFitInitializerMode", options.offsetFitInitializerMode, ...
                "offsetFitCoarseRetryRsquare", options.offsetFitCoarseRetryRsquare, ...
                "offsetFitCoarseGridStep_px", options.offsetFitCoarseGridStep_px, ...
                "offsetFitCoarseDownsampleFactor", options.offsetFitCoarseDownsampleFactor, ...
                "minimumOffsetFitRoiSize_px", options.minimumOffsetFitRoiSize_px);
        end

        function [dx, dy, gof] = estimate(model, image2D, fitDownsampleFactor)
            if nargin < 3
                fitDownsampleFactor = model.offsetFitDownsampleFactor;
            end
            if ~isequal(size(image2D), model.imageSize)
                error("attodryDisplacementFit:ImageSizeMismatch", ...
                    "Expected image size [%d, %d], received [%d, %d].", ...
                    model.imageSize(1), model.imageSize(2), size(image2D, 1), size(image2D, 2));
            end
            if any(~isfinite(double(image2D(:))))
                error("attodryDisplacementFit:InvalidCurrentImage", ...
                    "Current image contains non-finite values.");
            end
            switch model.sampleOffsetEstimatorMode
                case "spline_shift"
                    [dx, dy, gof] = attodryDisplacementFit.estimateSplineShift(model, image2D, fitDownsampleFactor);
                otherwise
                    error("attodryDisplacementFit:UnknownEstimator", ...
                        "Unknown sampleOffsetEstimatorMode ""%s"".", model.sampleOffsetEstimatorMode);
            end
        end

        function [fitRows, fitCols] = roiIndices(imageSize, roi, minimumRoiSize_px)
            if nargin < 3
                minimumRoiSize_px = [300, 300];
            end
            rows = imageSize(1);
            cols = imageSize(2);
            if all(isnan(roi))
                fitRows = 1:rows;
                fitCols = 1:cols;
            elseif any(~isfinite(roi)) || roi(3) <= 0 || roi(4) <= 0
                error("attodryDisplacementFit:InvalidOffsetFitRoi", ...
                    "offsetFitRoi_px must be all NaN or finite [x, y, width, height] with positive width and height.");
            else
                colStart = ceil(roi(1));
                rowStart = ceil(roi(2));
                colEnd = floor(roi(1) + roi(3) - 1);
                rowEnd = floor(roi(2) + roi(4) - 1);
                if rowStart < 1 || colStart < 1 || rowEnd > rows || colEnd > cols || rowStart > rowEnd || colStart > colEnd
                    error("attodryDisplacementFit:OffsetFitRoiOutOfBounds", ...
                        "offsetFitRoi_px [%g %g %g %g] is outside image size [%d %d].", roi, rows, cols);
                end
                fitRows = rowStart:rowEnd;
                fitCols = colStart:colEnd;
            end
            if numel(fitCols) < minimumRoiSize_px(1) || numel(fitRows) < minimumRoiSize_px(2)
                error("attodryDisplacementFit:OffsetFitRoiTooSmall", ...
                    "Offset-fit ROI must be at least %d x %d px. Received %d x %d px.", ...
                    minimumRoiSize_px(1), minimumRoiSize_px(2), numel(fitCols), numel(fitRows));
            end
        end

        function [fitRows, fitCols, rowShiftLimit, colShiftLimit, sampleRows, sampleCols] = ...
                sampleIndices(imageSize, roi, shiftFitTrimRatio, minimumRoiSize_px)
            if nargin < 4
                minimumRoiSize_px = [300, 300];
            end
            [fitRows, fitCols] = attodryDisplacementFit.roiIndices(imageSize, roi, minimumRoiSize_px);
            rowShiftLimit = ceil(shiftFitTrimRatio(1) / 2 * numel(fitRows));
            colShiftLimit = ceil(shiftFitTrimRatio(2) / 2 * numel(fitCols));
            if rowShiftLimit * 2 >= numel(fitRows) || colShiftLimit * 2 >= numel(fitCols)
                error("attodryDisplacementFit:TrimTooLarge", ...
                    "shiftFitTrimRatio leaves no offset fit samples inside the ROI.");
            end
            sampleRows = fitRows((rowShiftLimit + 1):(numel(fitRows) - rowShiftLimit));
            sampleCols = fitCols((colShiftLimit + 1):(numel(fitCols) - colShiftLimit));
        end
    end

    methods (Static, Access = private)
        function options = withDefaultOptions(options)
            defaults = struct( ...
                "offsetFitRoi_px", [NaN, NaN, NaN, NaN], ...
                "shiftFitTrimRatio", [0.4; 0.4], ...
                "minimumOffsetFitRoiSize_px", [300, 300], ...
                "sampleOffsetEstimatorMode", "spline_shift", ...
                "offsetFitDownsampleFactor", 1, ...
                "offsetFitInitializerMode", "fft_then_grid", ...
                "offsetFitCoarseRetryRsquare", -Inf, ...
                "offsetFitCoarseGridStep_px", 4, ...
                "offsetFitCoarseDownsampleFactor", 4);
            names = string(fieldnames(defaults));
            unknown = setdiff(string(fieldnames(options)), names);
            if ~isempty(unknown)
                error("attodryDisplacementFit:UnknownOption", ...
                    "Unknown displacement-fit option(s): %s.", strjoin(unknown, ", "));
            end
            for name = names.'
                fieldName = char(name);
                if ~isfield(options, fieldName)
                    options.(fieldName) = defaults.(fieldName);
                end
            end
            if ~isequal(size(options.offsetFitRoi_px), [1, 4]) ...
                    || ~isequal(size(options.shiftFitTrimRatio), [2, 1]) ...
                    || ~isequal(size(options.minimumOffsetFitRoiSize_px), [1, 2])
                error("attodryDisplacementFit:InvalidOptionSize", ...
                    "ROI, trim, and minimum ROI options have invalid sizes.");
            end
            options.sampleOffsetEstimatorMode = string(options.sampleOffsetEstimatorMode);
            options.offsetFitInitializerMode = string(options.offsetFitInitializerMode);
            if ~ismember(options.offsetFitInitializerMode, ["none", "fft", "grid", "fft_then_grid"])
                error("attodryDisplacementFit:UnknownInitializer", ...
                    "offsetFitInitializerMode must be none, fft, grid, or fft_then_grid.");
            end
        end

        function [dx, dy, gof] = estimateSplineShift(model, image2D, fitDownsampleFactor)
            currentFiltered = log(double(image2D) + 1);
            [rows, cols] = size(currentFiltered);
            [fullRows, fullCols] = ndgrid(1:rows, 1:cols);
            currentInterpolant = griddedInterpolant(fullRows, fullCols, currentFiltered, "spline", "none");
            sampleRows = model.sampleRows(1:fitDownsampleFactor:end);
            sampleCols = model.sampleCols(1:fitDownsampleFactor:end);
            [xGridTrimmed, yGridTrimmed] = ndgrid(sampleRows, sampleCols);
            zGridTrimmed = model.referenceFiltered(sampleRows, sampleCols);
            [fitResult, gof] = attodryDisplacementFit.fitSpline( ...
                currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model, [0, 0]);
            if gof.rsquare < model.offsetFitCoarseRetryRsquare
                if ismember(model.offsetFitInitializerMode, ["fft", "fft_then_grid"])
                    [startPoint, foundStart] = attodryDisplacementFit.estimateFftShift(currentFiltered, model);
                    if foundStart
                        [retryFitResult, retryGof] = attodryDisplacementFit.fitSpline( ...
                            currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model, startPoint);
                        if retryGof.rsquare > gof.rsquare
                            fitResult = retryFitResult;
                            gof = retryGof;
                        end
                    end
                end
                if gof.rsquare < model.offsetFitCoarseRetryRsquare ...
                        && ismember(model.offsetFitInitializerMode, ["grid", "fft_then_grid"])
                    startPoint = attodryDisplacementFit.estimateCoarseShiftGrid( ...
                        currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model);
                    [retryFitResult, retryGof] = attodryDisplacementFit.fitSpline( ...
                        currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model, startPoint);
                    if retryGof.rsquare > gof.rsquare
                        fitResult = retryFitResult;
                        gof = retryGof;
                    end
                end
            end
            dx = fitResult.dx;
            dy = fitResult.dy;
        end

        function [fitResult, gof] = fitSpline(currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model, startPoint)
            currentShiftFitModel = @(dx, dy, x, y) currentInterpolant(x + dx, y + dy);
            [fitResult, gof] = fit([xGridTrimmed(:), yGridTrimmed(:)], zGridTrimmed(:), currentShiftFitModel, ...
                StartPoint = startPoint, ...
                Lower = [-model.xTrim, -model.yTrim], ...
                Upper = [model.xTrim, model.yTrim], ...
                DiffMinChange = 0.00001, ...
                TolFun = 0.001, ...
                TolX = 0.001);
        end

        function [startPoint, foundStart] = estimateFftShift(currentFiltered, model)
            referencePatch = model.referenceFiltered(model.sampleRows, model.sampleCols);
            currentPatch = currentFiltered(model.sampleRows, model.sampleCols);
            referencePatch = attodryDisplacementFit.windowZeroMean(referencePatch);
            currentPatch = attodryDisplacementFit.windowZeroMean(currentPatch);
            if norm(referencePatch(:)) == 0 || norm(currentPatch(:)) == 0
                startPoint = [0, 0];
                foundStart = false;
                return;
            end
            crossPower = fft2(referencePatch) .* conj(fft2(currentPatch));
            magnitude = abs(crossPower);
            maxMagnitude = max(magnitude(:));
            if ~(isfinite(maxMagnitude) && maxMagnitude > 0)
                startPoint = [0, 0];
                foundStart = false;
                return;
            end
            correlation = real(ifft2(crossPower ./ max(magnitude, eps(maxMagnitude))));
            [~, linearIndex] = max(correlation(:));
            [rowIndex, colIndex] = ind2sub(size(correlation), linearIndex);
            rowShift = rowIndex - 1;
            colShift = colIndex - 1;
            if rowShift > floor(size(correlation, 1) / 2)
                rowShift = rowShift - size(correlation, 1);
            end
            if colShift > floor(size(correlation, 2) / 2)
                colShift = colShift - size(correlation, 2);
            end
            startPoint = [rowShift, colShift];
            foundStart = abs(rowShift) <= model.xTrim && abs(colShift) <= model.yTrim;
        end

        function patch = windowZeroMean(patch)
            patch = double(patch) - mean(double(patch(:)));
            rowWindow = attodryDisplacementFit.hannVector(size(patch, 1));
            colWindow = attodryDisplacementFit.hannVector(size(patch, 2)).';
            patch = patch .* (rowWindow * colWindow);
        end

        function vector = hannVector(n)
            if n <= 1
                vector = ones(n, 1);
            else
                vector = 0.5 - 0.5 * cos(2 * pi * (0:(n - 1)).' / (n - 1));
            end
        end

        function startPoint = estimateCoarseShiftGrid(currentInterpolant, xGridTrimmed, yGridTrimmed, zGridTrimmed, model)
            step = model.offsetFitCoarseGridStep_px;
            sampleStride = max(1, round(model.offsetFitCoarseDownsampleFactor / model.offsetFitDownsampleFactor));
            xGridTrimmed = xGridTrimmed(1:sampleStride:end, 1:sampleStride:end);
            yGridTrimmed = yGridTrimmed(1:sampleStride:end, 1:sampleStride:end);
            zGridTrimmed = zGridTrimmed(1:sampleStride:end, 1:sampleStride:end);
            rowCandidates = unique([(-model.xTrim):step:model.xTrim, 0, model.xTrim]);
            colCandidates = unique([(-model.yTrim):step:model.yTrim, 0, model.yTrim]);
            referenceValues = zGridTrimmed(:);
            bestSse = Inf;
            startPoint = [0, 0];
            for rowShift = rowCandidates
                shiftedRows = xGridTrimmed(:) + rowShift;
                for colShift = colCandidates
                    shiftedValues = currentInterpolant(shiftedRows, yGridTrimmed(:) + colShift);
                    sse = sum((referenceValues - shiftedValues).^2, "omitnan");
                    if sse < bestSse
                        bestSse = sse;
                        startPoint = [rowShift, colShift];
                    end
                end
            end
        end
    end
end
