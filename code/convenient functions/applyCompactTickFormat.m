function applyCompactTickFormat(axHandles)
% applyCompactTickFormat - Format numeric x/y tick labels with <=4 significant digits.
%
% Uses %.4g so MATLAB switches to scientific notation when shorter.

if nargin == 0 || isempty(axHandles)
    return;
end

axHandles = axHandles(isgraphics(axHandles, "axes"));
for idx = 1:numel(axHandles)
    ax = axHandles(idx);
    if isa(ax.XAxis, "matlab.graphics.axis.decorator.NumericRuler")
        xtickformat(ax, "%.4g");
    end
    if isa(ax.YAxis, "matlab.graphics.axis.decorator.NumericRuler")
        ytickformat(ax, "%.4g");
    end
end
end
