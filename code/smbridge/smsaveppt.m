% SAVEPPT saves plots to PowerPoint.
% function SAVEPPT(filespec,title,prnopt) saves the current Matlab figure
%  window or Simulink model window to a PowerPoint file designated by
%  filespec.  If filespec is omitted, the user is prompted to enter
%  one via UIPUTFILE.  If the path is omitted from filespec, the
%  PowerPoint file is created in the current Matlab working directory.
%
%  Optional input argument TITLE will add a title to the PowerPoint slide.
%
%  Optional input argument PRNOPT is used to specify additional save options:
%
%    -fHandle   Handle of figure window to save
%    -sName     Name of Simulink model window to save
%    -r###      Set bitmap resolution to ### dots/inch (This applies only to large
%               images which get converted to BMP when captured by the clipboard.)
%
%  Examples:
%  >> saveppt
%       Prompts user for valid filename and saves current figure
%  >> saveppt('junk.ppt')
%       Saves current figure to PowerPoint file called junk.ppt
%  >> saveppt('junk.ppt','Stock Price','-f3')
%       Saves figure #3 to PowerPoint file called junk.ppt with a
%       slide title of "Stock Price".
%  >> saveppt('models.ppt','System Block Diagram','-sMainBlock')
%       Saves Simulink model named "MainBlock" to file called models.ppt
%       with a slide title of "System Block Diagram".
%
%  The command-line method of invoking SAVEPPT will also work:
%  >> saveppt models.ppt 'System Block Diagram' -sMainBlock
%
%  However, if you want to save a specific figure or simulink model
%  without title text, you must use the function-call method:
%  >> saveppt('models.ppt','','-f8')
%
%Ver 2.2, Copyright 2005, Mark W. Brown, mwbrown@ieee.org
%  changed slide type to include title.
%  added input parameter for title text.
%  added support for int32 and single data types for Matlab 6.0
%  added comments about changing bitmap resolution (for large images only)
%  swapped order of opening PPT and copying to clipboard (thanks to David Abraham)
%  made PPT invisible during save operations (thanks to Noah Siegel)

function smsaveppt(filespec,text,prnopt)

% Establish valid file name:
if nargin<1 || isempty(filespec)
    return
else
    [fpath,fname,fext] = fileparts(filespec);
    if isempty(fpath); fpath = pwd; end
    if isempty(fext); fext = '.ppt'; end
    filespec = fullfile(fpath,[fname,fext]);
end

% Default title and body text:
if nargin<2
    text.title = '';
    text.body = '';
end
if ~isfield(text, "consts")
    text.consts = [];
end

% Start an ActiveX session with PowerPoint:
ppt = actxserver('PowerPoint.Application');

% Capture current figure/model into clipboard unless an image file is provided:
use_image_file = isfield(text, 'imagePath') && ~isempty(text.imagePath);
if ~use_image_file
    if nargin<3
        print -dmeta
    else
        print('-dmeta',prnopt)
    end
end

if ~exist(filespec,'file')
    % Create new presentation:
    op = invoke(ppt.Presentations,'Add');
else
    % First scan through open presentations
    numopen = ppt.Presentations.count;
    done = 0;
    for i = 1:numopen
        if strcmp(filespec,ppt.Presentations.Item(i).FullName)
            op = ppt.Presentations.Item(i);
            done = 1;
        end
    end
    % now open the file if it hasn't been found
    if done == 0
        op = ppt.Presentations.Open(filespec);
    end
end


% Get current number of slides:
slide_count = get(op.Slides,'Count');

% Add a new slide (with title object):
slide_count = int32(double(slide_count)+1);
new_slide = invoke(op.Slides,'Add',slide_count,11);

% Insert text into the title object:
set(new_slide.Shapes.Title.TextFrame.TextRange,'Text',text.title);
set(new_slide.Shapes.Title, 'Left', 100);
set(new_slide.Shapes.Title, 'Top', 0);
set(new_slide.Shapes.Title, 'Height', 30);
set(new_slide.Shapes.Title.TextFrame.TextRange.Font,'Size',single(20));
set(new_slide.Shapes.Title.TextFrame.TextRange.Font,'Bold',true);

% Get height and width of slide:
slide_H = op.PageSetup.SlideHeight;
slide_W = op.PageSetup.SlideWidth;
maxwidth = slide_W;
maxheight = slide_H - 100;
max_H_over_W = maxheight / maxwidth;

% Paste the contents of the Clipboard or insert image file:
%Thomas -07292022 added 2 retries
%Thomas -05262024 changed to infinite retries

if use_image_file
    img_info = imfinfo(text.imagePath);
    pic_H_over_W = double(img_info.Height) / double(img_info.Width);
    forceSlideWidth = isfield(text, "forceSlideWidth") && isscalar(text.forceSlideWidth) && logical(text.forceSlideWidth);
    if forceSlideWidth
        title_bottom = double(get(new_slide.Shapes.Title, "Top")) + double(get(new_slide.Shapes.Title, "Height"));
        pic_top = title_bottom;
        pic_H_scaled = slide_H - pic_top;
        pic_W_scaled = pic_H_scaled / pic_H_over_W;
        pic_left = (slide_W - pic_W_scaled) / 2;
    elseif max_H_over_W >= pic_H_over_W
        pic_W_scaled = maxwidth;
        pic_H_scaled = maxwidth * pic_H_over_W;
        pic_left = 0;
        pic_top = slide_H - pic_H_scaled;
    else
        pic_H_scaled = maxheight;
        pic_W_scaled = maxheight / pic_H_over_W;
        pic_left = 0;
        pic_top = slide_H - pic_H_scaled;
    end
    pic1 = invoke(new_slide.Shapes,'AddPicture', text.imagePath, 0, 1, ...
        single(pic_left), single(pic_top), single(pic_W_scaled), single(pic_H_scaled));
    try
        set(pic1, 'LockAspectRatio', true);
    catch
    end
else
    try
        pic1 = invoke(new_slide.Shapes,'Paste');
    catch
        success = false;
        while ~success
            try
                warning("Pasting screenshot into ppt failed. Retrying in 10 seconds... -Thomas");
                pause(10);
                if nargin<3
                    print -dmeta
                else
                    print('-dmeta',prnopt)
                end
                warning("Pasting into ppt in 10 seconds... -Thomas");
                pause(10);
                pic1 = invoke(new_slide.Shapes,'Paste');
                success = true;
            catch
            end
        end
    end
end

% Get height and width of picture and scale/position:
if ~use_image_file
    pic_H = get(pic1,'Height');
    pic_W = get(pic1,'Width');

    pic_H_over_W = pic_H / pic_W;

    if max_H_over_W >= pic_H_over_W
        pic_W_scaled = maxwidth;
        pic_H_scaled = maxwidth * pic_H_over_W;
    else
        pic_H_scaled = maxheight;
        pic_W_scaled = maxheight / pic_H_over_W;
    end
    %pic_W_scaled = pic_W_scaled * 2;
    %pic_H_scaled = pic_H_scaled * 2;
    set(pic1,'Height', pic_H_scaled);
    set(pic1,'Width', pic_W_scaled);
    set(pic1,'Left',0);
    set(pic1,'Top', slide_H - pic_H_scaled);
end

% if (pic_H > maxheight || pic_W > maxwidth)
%     if (pic_H/425 > pic_W/525)
%         set(pic1,'Height',single(maxheight));
%     else
%         set(pic1,'Width',single(maxwidth));
%     end
% end

% Center picture on right 3/4 of page (below title area):
%set(pic1,'Left',single(180));
%set(pic1,'Top',single(108));



blocks = strings(0, 1);

if isfield(text, "header") && ~isempty(text.header)
    headerLines = splitlines(string(text.header));
    headerLines = strtrim(headerLines);
    headerLines = headerLines(strlength(headerLines) > 0);
    if ~isempty(headerLines)
        blocks(end+1) = strjoin(headerLines, "; ");
    end
end

if ~isempty(text.consts)
    consts = text.consts;
    if ~isfield(consts, "set")
        [consts.set] = deal(1);
    end
    setMask = [consts.set] == 1;
    getMask = ~setMask;

    if any(setMask)
        setConsts = consts(setMask);
        setItems = strings(1, numel(setConsts));
        for i = 1:numel(setConsts)
            setItems(i) = sprintf("%s = %.3g", string(setConsts(i).setchan), setConsts(i).val);
        end
        blocks(end+1) = "set constants: " + strjoin(setItems, "; ");
    end

    if any(getMask)
        getConsts = consts(getMask);
        getItems = strings(1, numel(getConsts));
        for i = 1:numel(getConsts)
            getItems(i) = sprintf("%s = %.3g", string(getConsts(i).setchan), getConsts(i).val);
        end
        blocks(end+1) = "get constants: " + strjoin(getItems, "; ");
    end
end

if isfield(text, "body") && ~isempty(text.body)
    bodyLines = splitlines(string(text.body));
    bodyLines = strtrim(bodyLines);
    bodyLines = bodyLines(strlength(bodyLines) > 0);
    if ~isempty(bodyLines)
        blocks(end+1) = strjoin(bodyLines, "; ");
    end
end

if isempty(blocks)
    g = "";
else
    g = strjoin(blocks, ";; ");
end



% Make a textbox for comments
text1 = invoke(new_slide.Shapes(1),'AddTextbox',1,single(300),single(0),single(600),single(100));
set(text1.TextFrame.TextRange.Font,'Size',single(9));
set(text1.TextFrame.TextRange,'Text',char(g));

% Make a textbox for timestamp
text2 = invoke(new_slide.Shapes(1),'AddTextbox',1,single(0),single(0),single(175),single(100));
set(text2.TextFrame.TextRange.Font,'Size',single(9));
invoke(text2.TextFrame.TextRange,'InsertDateTime','ppDateTimeMMddyyHmm');


if ~exist(filespec,'file')
    % Save file as new:
    invoke(op,'SaveAs',filespec,1);
else
    % Save existing file:
    invoke(op,'Save');
end



% % Close the presentation window:
% invoke(op,'Close');
%
% % Quit PowerPoint
% invoke(ppt,'Quit');

return
