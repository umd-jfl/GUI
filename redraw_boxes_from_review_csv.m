function redraw_boxes_from_review_csv()
%% redraw_boxes_from_review_csv.m
%
% Reapply saved boxes, labels, ObjectID, and ContactID to original images.
%
% This script reads the reviewed CSV exported by maritime_label_detect_track_gui.m
% and creates new annotated images from the original images.
%
% Typical use cases:
%   - Recreate annotated images after changing color rules
%   - Generate presentation/report images from the saved CSV
%   - Verify exported annotations without reopening the GUI
%   - Apply the same boxes to original images after moving output folders

clear; clc; close all;

%% ================= USER SETTINGS =================

csvPath = fullfile("LaRS_Label_Detect_Track_Output", "reviewed_detections_all.csv");
redrawOutputDir = fullfile("LaRS_Label_Detect_Track_Output", "redrawn_from_csv");

% If true and CSV contains BoxColorR/G/B columns, use those saved colors.
% If false, recompute colors using redrawBoxColorMode below.
useSavedCsvColors = true;

% Used only when useSavedCsvColors = false.
% Supported: "label", "contactID", "single"
redrawBoxColorMode = "label";
defaultBoxColor = [255 255 0];

labelColorMap = containers.Map( ...
    {'boat','ship','submarine','cargo_ship','warship','aircraft_carrier', ...
     'sailboat','fishing_boat','passenger_ship','airplane','helicopter', ...
     'bird','buoy','dock','unknown','none'}, ...
    {[0 255 255], [255 255 0], [255 0 255], [255 128 0], [255 0 0], [128 0 255], ...
     [0 255 0], [0 128 255], [128 255 0], [0 0 255], [128 128 255], ...
     [0 255 128], [255 128 128], [128 128 128], [255 255 255], [255 255 255]} ...
);

contactIDColorSeed = 37;

includeObjectIDInText = true;
includeContactIDInText = true;
includeConfidenceInText = true;

% If FullPath from the CSV no longer exists, set this to the new image folder.
fallbackImageFolder = "";

%% ================= VALIDATION =================

if ~isfile(csvPath)
    error("CSV file not found: %s", csvPath);
end
if ~exist(redrawOutputDir, "dir"); mkdir(redrawOutputDir); end

T = readtable(csvPath, TextType="string");
requiredColumns = ["Frame","FullPath","FrameIndex","ObjectID","ContactID","Label","X1","Y1","Width","Height"];
missingColumns = requiredColumns(~ismember(requiredColumns, string(T.Properties.VariableNames)));
if ~isempty(missingColumns)
    error("CSV is missing required columns: %s", strjoin(missingColumns, ", "));
end

fprintf("Loaded CSV rows: %d\n", height(T));

%% ================= GROUP BY FRAME =================

frameKeys = unique(T.FrameIndex);

for k = 1:numel(frameKeys)
    frameIndex = frameKeys(k);
    rows = T(T.FrameIndex == frameIndex, :);
    if isempty(rows); continue; end

    imagePath = resolveImagePath(rows.FullPath(1), rows.Frame(1), fallbackImageFolder);
    if imagePath == ""
        warning("Could not locate image for frame %s. Skipping.", string(rows.Frame(1)));
        continue;
    end

    I = imread(imagePath);
    annotated = I;

    validRows = ~isnan(rows.X1) & ~isnan(rows.Y1) & ~isnan(rows.Width) & ~isnan(rows.Height) & rows.Width > 1 & rows.Height > 1;

    if any(validRows)
        validData = rows(validRows, :);
        for r = 1:height(validData)
            bbox = [round(validData.X1(r)), round(validData.Y1(r)), round(validData.Width(r)), round(validData.Height(r))];
            labelText = makeAnnotationText(validData(r, :));
            color = getRowColor(validData(r, :));
            annotated = insertObjectAnnotation(annotated, "rectangle", bbox, labelText, "Color", uint8(color));
        end
    end

    [~, baseName, ~] = fileparts(imagePath);
    outFile = fullfile(redrawOutputDir, sprintf("%06d_%s_redrawn.png", frameIndex, baseName));
    imwrite(annotated, outFile);
    fprintf("Saved: %s\n", outFile);
end

fprintf("\nRedraw complete. Output folder:\n%s\n", redrawOutputDir);

%% ========================================================================
% HELPER FUNCTIONS
% ========================================================================

    function imagePath = resolveImagePath(fullPathFromCsv, frameName, fallbackFolder)
        imagePath = string(fullPathFromCsv);
        if isfile(imagePath); return; end
        if fallbackFolder == "" || ~isfolder(fallbackFolder)
            imagePath = ""; return;
        end
        possibleExts = [".jpg",".jpeg",".png",".bmp",".tif",".tiff"];
        for ii = 1:numel(possibleExts)
            candidate = fullfile(fallbackFolder, string(frameName) + possibleExts(ii));
            if isfile(candidate); imagePath = string(candidate); return; end
        end
        listing = dir(fullfile(fallbackFolder, "**", "*"));
        for ii = 1:numel(listing)
            if listing(ii).isdir; continue; end
            [~, nameOnly, ext] = fileparts(listing(ii).name);
            if string(nameOnly) == string(frameName) && any(lower(string(ext)) == possibleExts)
                imagePath = string(fullfile(listing(ii).folder, listing(ii).name)); return;
            end
        end
        imagePath = "";
    end

    function labelText = makeAnnotationText(row)
        labelText = string(row.Label);
        if includeObjectIDInText
            oid = strip(string(row.ObjectID));
            if oid ~= ""; labelText = labelText + " ID:" + oid; end
        end
        if includeContactIDInText
            cid = strip(string(row.ContactID));
            if cid ~= ""; labelText = labelText + " CID:" + cid; end
        end
        if includeConfidenceInText && ismember("Confidence", string(row.Properties.VariableNames))
            conf = row.Confidence;
            if ~isnan(conf); labelText = labelText + " " + compose("%.2f", conf); else; labelText = labelText + " manual"; end
        end
    end

    function c = getRowColor(row)
        hasSavedColors = all(ismember(["BoxColorR","BoxColorG","BoxColorB"], string(row.Properties.VariableNames)));
        if useSavedCsvColors && hasSavedColors && ~isnan(row.BoxColorR) && ~isnan(row.BoxColorG) && ~isnan(row.BoxColorB)
            c = [row.BoxColorR, row.BoxColorG, row.BoxColorB]; return;
        end
        switch lower(string(redrawBoxColorMode))
            case "label"
                key = char(string(row.Label));
                if isKey(labelColorMap, key); c = labelColorMap(key); else; c = defaultBoxColor; end
            case "contactid"
                cid = string(row.ContactID);
                if strip(cid) == ""; c = defaultBoxColor; else; c = deterministicColorFromString(cid, contactIDColorSeed); end
            case "single"
                c = defaultBoxColor;
            otherwise
                c = defaultBoxColor;
        end
    end

    function c = deterministicColorFromString(strValue, seed)
        s = char(string(strValue));
        if isempty(s); c = defaultBoxColor; return; end
        hashValue = seed;
        for kk = 1:numel(s)
            hashValue = mod(hashValue * 31 + double(s(kk)), 9973);
        end
        hue = mod(hashValue, 360) / 360;
        c = round(hsv2rgb([hue 0.75 1.00]) * 255);
    end
end
