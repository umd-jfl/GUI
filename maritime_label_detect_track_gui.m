function maritime_label_detect_track_gui()
%% maritime_label_detect_track_gui.m
% Maritime Labeling, Object Detection, and Tracking Review GUI
%
% This GUI is intended for:
%   1. Manual image labeling
%   2. Pretrained or custom object detection review
%   3. Human-in-the-loop object tracking using persistent ContactID values
%
% Detector modes:
%   "none"       : no automatic model; user manually labels boxes.
%   "pretrained" : use MATLAB pretrained YOLOv4 detector.
%   "custom"     : load a custom detector from a .mat file.
%
% Run:
%   maritime_label_detect_track_gui

clear; clc; close all;

%% ================= USER SETTINGS =================

inputDir = fullfile("lars_v1.0.0_images", "val", "images");
outputDir = "LaRS_Label_Detect_Track_Output";

detectorMode = "pretrained";   % "none", "pretrained", or "custom"
pretrainedDetectorName = "tiny-yolov4-coco";
customModelPath = fullfile("models", "maritimeDetector.mat");
confidenceThreshold = 0.25;
keepAllDetectedClasses = false;

targetClasses = [
    "boat"
    "airplane"
    "bird"
];

manualLabels = [
    "boat"
    "ship"
    "submarine"
    "cargo_ship"
    "warship"
    "aircraft_carrier"
    "sailboat"
    "fishing_boat"
    "passenger_ship"
    "airplane"
    "helicopter"
    "bird"
    "buoy"
    "dock"
    "unknown"
];

defaultManualLabel = "ship";
startFrameIndex = 1;
maxImagesToLoad = 200;       % Use Inf for all images.
exportEmptyFrameRows = true; % Export no-box frames as negative rows.
defaultContactID = "";

%% ================= BOUNDING BOX COLOR SETTINGS =================
% These settings control the colors used when SAVING annotated images.
% They do not change the live interactive ROI colors on screen.
%
% Supported modes:
%   "label"     : color boxes by object label
%   "contactID" : color boxes by persistent ContactID
%   "source"    : color boxes by detection/edit source
%   "single"    : use one color for every box
%
% Colors are RGB triplets in [R G B] format from 0 to 255.
boxColorMode = "label";
defaultBoxColor = [255 255 0];   % yellow fallback

labelColorMap = containers.Map( ...
    {'boat','ship','submarine','cargo_ship','warship','aircraft_carrier', ...
     'sailboat','fishing_boat','passenger_ship','airplane','helicopter', ...
     'bird','buoy','dock','unknown'}, ...
    {[0 255 255], [255 255 0], [255 0 255], [255 128 0], [255 0 0], [128 0 255], ...
     [0 255 0], [0 128 255], [128 255 0], [0 0 255], [128 128 255], ...
     [0 255 128], [255 128 128], [128 128 128], [255 255 255]} ...
);

sourceColorMap = containers.Map( ...
    {'pretrained','custom','manual','pretrained_edited','custom_edited','manual_edited','none'}, ...
    {[255 255 0], [0 255 0], [0 255 255], [255 128 0], [128 255 0], [0 128 255], [255 255 255]} ...
);

% Used when boxColorMode = "contactID". Same ContactID gets same deterministic color.
contactIDColorSeed = 37;

%% ================= VALIDATE INPUT =================

if ~isfolder(inputDir)
    error("Input folder not found: %s", inputDir);
end

%% ================= OUTPUT FOLDERS =================

if ~exist(outputDir, "dir"); mkdir(outputDir); end

annotatedDir = fullfile(outputDir, "reviewed_annotated");
cropDir      = fullfile(outputDir, "reviewed_crops");
pixelDir     = fullfile(outputDir, "reviewed_pixels");

if ~exist(annotatedDir, "dir"); mkdir(annotatedDir); end
if ~exist(cropDir, "dir"); mkdir(cropDir); end
if ~exist(pixelDir, "dir"); mkdir(pixelDir); end

%% ================= LOAD DETECTOR =================

detector = [];
detectorDescription = "No detector";

switch lower(detectorMode)
    case "none"
        fprintf("\nDetector mode: none. GUI will open without automatic boxes.\n");
        detector = [];
        detectorDescription = "None";

    case "pretrained"
        fprintf("\nLoading pretrained detector: %s\n", pretrainedDetectorName);
        detector = yolov4ObjectDetector(pretrainedDetectorName);
        detectorDescription = "Pretrained: " + pretrainedDetectorName;
        fprintf("Detector loaded.\n");

    case "custom"
        fprintf("\nLoading custom detector from: %s\n", customModelPath);
        if ~isfile(customModelPath)
            error("Custom model file not found: %s", customModelPath);
        end
        modelData = load(customModelPath);
        if isfield(modelData, "detector")
            detector = modelData.detector;
        elseif isfield(modelData, "trainedDetector")
            detector = modelData.trainedDetector;
        elseif isfield(modelData, "maritimeDetector")
            detector = modelData.maritimeDetector;
        else
            error("No detector variable found. Expected detector, trainedDetector, or maritimeDetector.");
        end
        detectorDescription = "Custom: " + string(customModelPath);
        fprintf("Custom detector loaded.\n");

    otherwise
        error("Invalid detectorMode: %s. Use none, pretrained, or custom.", detectorMode);
end

%% ================= LOAD IMAGE LIST =================

fprintf("\nSearching for images under:\n%s\n", inputDir);
imageFiles = findImagesRecursive(inputDir);
if isempty(imageFiles)
    error("No images found under inputDir: %s", inputDir);
end
if isfinite(maxImagesToLoad)
    imageFiles = imageFiles(1:min(maxImagesToLoad, numel(imageFiles)));
end
numImages = numel(imageFiles);
fprintf("Images loaded: %d\n", numImages);

%% ================= INTERNAL STATE =================

currentIndex = max(1, min(startFrameIndex, numImages));
frameData = struct();

for i = 1:numImages
    frameData(i).imagePath = imageFiles(i);
    frameData(i).detected = false;
    frameData(i).reviewed = false;
    frameData(i).frameStatus = "unreviewed";
    frameData(i).boxes = makeEmptyBoxesStruct();
end

currentImage = [];
currentROIHandles = images.roi.Rectangle.empty;
selectedROIIndex = [];
knownContactIDs = strings(0,1);

%% ================= GUI LAYOUT =================

fig = uifigure("Name", "Maritime Labeling, Detection, and Tracking GUI", "Position", [80 80 1550 900]);
mainGrid = uigridlayout(fig, [1 2]);
mainGrid.ColumnWidth = {'3x', '1.15x'};

leftPanel = uipanel(mainGrid, "Title", "Image Review");
leftGrid = uigridlayout(leftPanel, [2 1]);
leftGrid.RowHeight = {'1x', 45};
ax = uiaxes(leftGrid);
ax.XTick = [];
ax.YTick = [];
ax.Box = "on";
statusLabel = uilabel(leftGrid, "Text", "Ready", "FontWeight", "bold");

rightPanel = uipanel(mainGrid, "Title", "Controls");
rightGrid = uigridlayout(rightPanel, [22 2]);
rightGrid.RowHeight = {34,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,30,'1x',30,30,30};
rightGrid.ColumnWidth = {'1x','1x'};

modelText = uilabel(rightGrid, "Text", "Detector: " + detectorDescription, "WordWrap", "on");
modelText.Layout.Row = 1; modelText.Layout.Column = [1 2];
frameText = uilabel(rightGrid, "Text", "Frame:");
frameText.Layout.Row = 2; frameText.Layout.Column = [1 2];
fileText = uilabel(rightGrid, "Text", "File:", "WordWrap", "on");
fileText.Layout.Row = 3; fileText.Layout.Column = [1 2];
statusText = uilabel(rightGrid, "Text", "Status:");
statusText.Layout.Row = 4; statusText.Layout.Column = [1 2];

jumpIndexField = uieditfield(rightGrid, "numeric", "Limits", [1 numImages], "RoundFractionalValues", "on", "Value", currentIndex);
jumpIndexField.Layout.Row = 5; jumpIndexField.Layout.Column = 1;
jumpButton = uibutton(rightGrid, "Text", "Go To Frame", "ButtonPushedFcn", @(~,~) goToFrame());
jumpButton.Layout.Row = 5; jumpButton.Layout.Column = 2;

prevButton = uibutton(rightGrid, "Text", "Previous", "ButtonPushedFcn", @(~,~) goPrevious());
prevButton.Layout.Row = 6; prevButton.Layout.Column = 1;
nextButton = uibutton(rightGrid, "Text", "Next", "ButtonPushedFcn", @(~,~) goNext());
nextButton.Layout.Row = 6; nextButton.Layout.Column = 2;

goodButton = uibutton(rightGrid, "Text", "Mark Good", "ButtonPushedFcn", @(~,~) markFrame("good"));
goodButton.Layout.Row = 7; goodButton.Layout.Column = 1;
badButton = uibutton(rightGrid, "Text", "Mark Bad", "ButtonPushedFcn", @(~,~) markFrame("bad"));
badButton.Layout.Row = 7; badButton.Layout.Column = 2;
unreviewedButton = uibutton(rightGrid, "Text", "Mark Unreviewed", "ButtonPushedFcn", @(~,~) markFrame("unreviewed"));
unreviewedButton.Layout.Row = 8; unreviewedButton.Layout.Column = [1 2];

addButton = uibutton(rightGrid, "Text", "Add Box", "ButtonPushedFcn", @(~,~) addBox());
addButton.Layout.Row = 9; addButton.Layout.Column = 1;
deleteButton = uibutton(rightGrid, "Text", "Delete Selected", "ButtonPushedFcn", @(~,~) deleteSelectedBox());
deleteButton.Layout.Row = 9; deleteButton.Layout.Column = 2;

labelDropDown = uidropdown(rightGrid, "Items", cellstr(manualLabels), "Value", char(defaultManualLabel));
labelDropDown.Layout.Row = 10; labelDropDown.Layout.Column = 1;
applyLabelButton = uibutton(rightGrid, "Text", "Apply Label", "ButtonPushedFcn", @(~,~) applySelectedLabel());
applyLabelButton.Layout.Row = 10; applyLabelButton.Layout.Column = 2;

contactIDField = uieditfield(rightGrid, "text", "Value", char(defaultContactID), "Placeholder", "Type ContactID");
contactIDField.Layout.Row = 11; contactIDField.Layout.Column = 1;
applyContactIDButton = uibutton(rightGrid, "Text", "Apply ContactID", "ButtonPushedFcn", @(~,~) applySelectedContactID());
applyContactIDButton.Layout.Row = 11; applyContactIDButton.Layout.Column = 2;

contactIDDropDown = uidropdown(rightGrid, "Items", {'<none>'}, "Value", '<none>');
contactIDDropDown.Layout.Row = 12; contactIDDropDown.Layout.Column = 1;
useExistingContactIDButton = uibutton(rightGrid, "Text", "Use Existing ID", "ButtonPushedFcn", @(~,~) useExistingContactID());
useExistingContactIDButton.Layout.Row = 12; useExistingContactIDButton.Layout.Column = 2;

rerunButton = uibutton(rightGrid, "Text", "Run/Reload Model", "ButtonPushedFcn", @(~,~) rerunDetectorOnCurrentFrame());
rerunButton.Layout.Row = 13; rerunButton.Layout.Column = 1;
clearButton = uibutton(rightGrid, "Text", "Clear Boxes", "ButtonPushedFcn", @(~,~) clearCurrentBoxes());
clearButton.Layout.Row = 13; clearButton.Layout.Column = 2;

saveFrameButton = uibutton(rightGrid, "Text", "Save Current Frame", "ButtonPushedFcn", @(~,~) saveCurrentFrameOnly());
saveFrameButton.Layout.Row = 14; saveFrameButton.Layout.Column = [1 2];
exportButton = uibutton(rightGrid, "Text", "Export All Results", "FontWeight", "bold", "ButtonPushedFcn", @(~,~) exportAllResults());
exportButton.Layout.Row = 15; exportButton.Layout.Column = [1 2];

helpText = uitextarea(rightGrid, "Editable", "off");
helpText.Value = {'Instructions:';'1. Model boxes load unless detectorMode = none.';'2. Click a box or table row to select it.';'3. Drag/resize boxes on image.';'4. Use Add Box to draw a missing object.';'5. Edit ObjectID, ContactID, and Label in table.';'6. Use ContactID to track same object across frames.';'7. Save && Next exports current frame.';'8. Export All Results saves all frames, including empty frames.'};
helpText.Layout.Row = [16 18]; helpText.Layout.Column = [1 2];

boxTable = uitable(rightGrid);
boxTable.Layout.Row = 19; boxTable.Layout.Column = [1 2];
boxTable.ColumnName = {'ObjectID', 'ContactID', 'Label', 'Confidence', 'X', 'Y', 'W', 'H', 'Source'};
boxTable.ColumnEditable = [true true true false false false false false false];
boxTable.CellSelectionCallback = @(src,event) tableSelectionChanged(event);
boxTable.CellEditCallback = @(src,event) tableCellEdited(event);

progressText = uilabel(rightGrid, "Text", "Progress:");
progressText.Layout.Row = 20; progressText.Layout.Column = [1 2];
saveAndNextButton = uibutton(rightGrid, "Text", "Save && Next", "ButtonPushedFcn", @(~,~) saveAndNext());
saveAndNextButton.Layout.Row = 21; saveAndNextButton.Layout.Column = [1 2];
trackingSummaryButton = uibutton(rightGrid, "Text", "Show ContactID Summary", "ButtonPushedFcn", @(~,~) showContactIDSummary());
trackingSummaryButton.Layout.Row = 22; trackingSummaryButton.Layout.Column = [1 2];

%% ================= START GUI =================
loadFrame(currentIndex);

%% ========================================================================
% CALLBACK FUNCTIONS
% ========================================================================

    function loadFrame(index)
        if ~isempty(currentImage)
            saveCurrentROIsToMemory();
        end
        currentIndex = max(1, min(index, numImages));
        selectedROIIndex = [];
        imgPath = frameData(currentIndex).imagePath;
        currentImage = imread(imgPath);
        if ~frameData(currentIndex).detected
            runDetectorForFrame(currentIndex);
        end
        refreshDisplay();
    end

    function runDetectorForFrame(index)
        imgPath = frameData(index).imagePath;
        I = imread(imgPath);
        boxes = makeEmptyBoxesStruct();
        if lower(detectorMode) == "none" || isempty(detector)
            frameData(index).boxes = boxes;
            frameData(index).detected = true;
            return;
        end
        [bboxes, scores, labels] = detect(detector, I, Threshold=confidenceThreshold);
        labels = string(labels);
        if ~keepAllDetectedClasses
            keepIdx = ismember(labels, targetClasses);
            bboxes = bboxes(keepIdx, :);
            scores = scores(keepIdx);
            labels = labels(keepIdx);
        end
        for j = 1:size(bboxes, 1)
            boxes(j).ObjectID = string(j);
            boxes(j).ContactID = "";
            boxes(j).Label = labels(j);
            boxes(j).Confidence = scores(j);
            boxes(j).Position = bboxes(j, :);
            boxes(j).Source = detectorMode;
        end
        frameData(index).boxes = boxes;
        frameData(index).detected = true;
    end

    function refreshDisplay()
        deleteCurrentROIHandles();
        cla(ax);
        imshow(currentImage, "Parent", ax);
        hold(ax, "on");
        boxes = frameData(currentIndex).boxes;
        currentROIHandles = images.roi.Rectangle.empty;
        for j = 1:numel(boxes)
            pos = boxes(j).Position;
            roi = drawrectangle(ax, "Position", pos, "Label", makeROILabel(boxes(j)), "InteractionsAllowed", "all");
            roi.UserData = j;
            addlistener(roi, "ROIClicked", @(src,event) roiClicked(src));
            addlistener(roi, "ROIMoved", @(src,event) roiMoved(src));
            currentROIHandles(j) = roi; %#ok<AGROW>
        end
        hold(ax, "off");
        updateTextLabels();
        refreshBoxTable();
    end

    function updateTextLabels()
        [~, name, ext] = fileparts(frameData(currentIndex).imagePath);
        frameText.Text = sprintf("Frame: %d / %d", currentIndex, numImages);
        fileText.Text = sprintf("File: %s%s", name, ext);
        statusText.Text = sprintf("Status: %s | Boxes: %d", frameData(currentIndex).frameStatus, numel(frameData(currentIndex).boxes));
        reviewedArray = false(1, numImages);
        for ii = 1:numImages
            reviewedArray(ii) = frameData(ii).reviewed;
        end
        progressText.Text = sprintf("Reviewed: %d / %d | ContactIDs: %d", sum(reviewedArray), numImages, numel(knownContactIDs));
        statusLabel.Text = sprintf("Frame %d/%d | %s | Status: %s", currentIndex, numImages, frameData(currentIndex).imagePath, frameData(currentIndex).frameStatus);
        jumpIndexField.Value = currentIndex;
    end

    function refreshBoxTable()
        saveCurrentROIsToMemory();
        boxes = frameData(currentIndex).boxes;
        if isempty(boxes)
            boxTable.Data = {};
            return;
        end
        tableData = cell(numel(boxes), 9);
        for j = 1:numel(boxes)
            pos = boxes(j).Position;
            tableData{j,1} = char(string(boxes(j).ObjectID));
            tableData{j,2} = char(string(boxes(j).ContactID));
            tableData{j,3} = char(string(boxes(j).Label));
            tableData{j,4} = boxes(j).Confidence;
            tableData{j,5} = round(pos(1));
            tableData{j,6} = round(pos(2));
            tableData{j,7} = round(pos(3));
            tableData{j,8} = round(pos(4));
            tableData{j,9} = char(string(boxes(j).Source));
        end
        boxTable.Data = tableData;
    end

    function roiClicked(src)
        selectedROIIndex = src.UserData;
        if selectedROIIndex >= 1 && selectedROIIndex <= numel(frameData(currentIndex).boxes)
            contactIDField.Value = char(string(frameData(currentIndex).boxes(selectedROIIndex).ContactID));
            currentLabel = string(frameData(currentIndex).boxes(selectedROIIndex).Label);
            if any(manualLabels == currentLabel)
                labelDropDown.Value = char(currentLabel);
            end
        end
        highlightSelectedROI();
    end

    function roiMoved(src)
        idx = src.UserData;
        if idx >= 1 && idx <= numel(frameData(currentIndex).boxes)
            frameData(currentIndex).boxes(idx).Position = src.Position;
            frameData(currentIndex).boxes(idx).Source = appendEditedSuffix(frameData(currentIndex).boxes(idx).Source);
        end
        refreshBoxTable();
    end

    function highlightSelectedROI()
        for j = 1:numel(currentROIHandles)
            if isvalid(currentROIHandles(j)); currentROIHandles(j).LineWidth = 1; end
        end
        if ~isempty(selectedROIIndex) && selectedROIIndex >= 1 && selectedROIIndex <= numel(currentROIHandles)
            if isvalid(currentROIHandles(selectedROIIndex)); currentROIHandles(selectedROIIndex).LineWidth = 4; end
        end
    end

    function tableSelectionChanged(event)
        if isempty(event.Indices); return; end
        selectedROIIndex = event.Indices(1);
        if selectedROIIndex >= 1 && selectedROIIndex <= numel(frameData(currentIndex).boxes)
            contactIDField.Value = char(string(frameData(currentIndex).boxes(selectedROIIndex).ContactID));
            currentLabel = string(frameData(currentIndex).boxes(selectedROIIndex).Label);
            if any(manualLabels == currentLabel); labelDropDown.Value = char(currentLabel); end
        end
        highlightSelectedROI();
    end

    function tableCellEdited(event)
        row = event.Indices(1);
        col = event.Indices(2);
        if row < 1 || row > numel(frameData(currentIndex).boxes); return; end
        newValue = string(event.NewData);
        switch col
            case 1
                frameData(currentIndex).boxes(row).ObjectID = newValue;
            case 2
                frameData(currentIndex).boxes(row).ContactID = newValue;
                contactIDField.Value = char(newValue);
                registerContactID(newValue);
            case 3
                frameData(currentIndex).boxes(row).Label = newValue;
                if any(manualLabels == newValue); labelDropDown.Value = char(newValue); end
                if row <= numel(currentROIHandles) && isvalid(currentROIHandles(row))
                    currentROIHandles(row).Label = makeROILabel(frameData(currentIndex).boxes(row));
                end
            otherwise
                return;
        end
        frameData(currentIndex).boxes(row).Source = appendEditedSuffix(frameData(currentIndex).boxes(row).Source);
        refreshBoxTable();
        refreshDisplay();
    end

    function addBox()
        saveCurrentROIsToMemory();
        selectedLabel = string(labelDropDown.Value);
        selectedContactID = strip(string(contactIDField.Value));
        roi = drawrectangle(ax, "Label", char(selectedLabel), "InteractionsAllowed", "all");
        if isempty(roi) || ~isvalid(roi); return; end
        newIdx = numel(frameData(currentIndex).boxes) + 1;
        frameData(currentIndex).boxes(newIdx).ObjectID = string(newIdx);
        frameData(currentIndex).boxes(newIdx).ContactID = selectedContactID;
        frameData(currentIndex).boxes(newIdx).Label = selectedLabel;
        frameData(currentIndex).boxes(newIdx).Confidence = NaN;
        frameData(currentIndex).boxes(newIdx).Position = roi.Position;
        frameData(currentIndex).boxes(newIdx).Source = "manual";
        registerContactID(selectedContactID);
        roi.UserData = newIdx;
        roi.Label = makeROILabel(frameData(currentIndex).boxes(newIdx));
        addlistener(roi, "ROIClicked", @(src,event) roiClicked(src));
        addlistener(roi, "ROIMoved", @(src,event) roiMoved(src));
        currentROIHandles(newIdx) = roi;
        selectedROIIndex = newIdx;
        refreshBoxTable(); highlightSelectedROI(); updateTextLabels();
    end

    function deleteSelectedBox()
        saveCurrentROIsToMemory();
        if isempty(selectedROIIndex)
            uialert(fig, "Select a bounding box first.", "No Box Selected"); return;
        end
        boxes = frameData(currentIndex).boxes;
        if selectedROIIndex < 1 || selectedROIIndex > numel(boxes); return; end
        boxes(selectedROIIndex) = [];
        frameData(currentIndex).boxes = boxes;
        selectedROIIndex = [];
        reassignObjectIDsIfMissing();
        refreshDisplay();
    end

    function applySelectedLabel()
        if isempty(selectedROIIndex)
            uialert(fig, "Select a bounding box first.", "No Box Selected"); return;
        end
        newLabel = string(labelDropDown.Value);
        if selectedROIIndex >= 1 && selectedROIIndex <= numel(frameData(currentIndex).boxes)
            frameData(currentIndex).boxes(selectedROIIndex).Label = newLabel;
            frameData(currentIndex).boxes(selectedROIIndex).Source = appendEditedSuffix(frameData(currentIndex).boxes(selectedROIIndex).Source);
            if selectedROIIndex <= numel(currentROIHandles) && isvalid(currentROIHandles(selectedROIIndex))
                currentROIHandles(selectedROIIndex).Label = makeROILabel(frameData(currentIndex).boxes(selectedROIIndex));
            end
        end
        refreshBoxTable();
    end

    function applySelectedContactID()
        if isempty(selectedROIIndex)
            uialert(fig, "Select a bounding box first.", "No Box Selected"); return;
        end
        newContactID = strip(string(contactIDField.Value));
        if selectedROIIndex >= 1 && selectedROIIndex <= numel(frameData(currentIndex).boxes)
            frameData(currentIndex).boxes(selectedROIIndex).ContactID = newContactID;
            frameData(currentIndex).boxes(selectedROIIndex).Source = appendEditedSuffix(frameData(currentIndex).boxes(selectedROIIndex).Source);
            registerContactID(newContactID);
            if selectedROIIndex <= numel(currentROIHandles) && isvalid(currentROIHandles(selectedROIIndex))
                currentROIHandles(selectedROIIndex).Label = makeROILabel(frameData(currentIndex).boxes(selectedROIIndex));
            end
        end
        refreshBoxTable(); updateTextLabels();
    end

    function useExistingContactID()
        if isempty(selectedROIIndex)
            uialert(fig, "Select a bounding box first.", "No Box Selected"); return;
        end
        selectedContactID = string(contactIDDropDown.Value);
        if selectedContactID == "<none>" || selectedContactID == ""
            uialert(fig, "Select an existing ContactID first.", "No ContactID Selected"); return;
        end
        if selectedROIIndex >= 1 && selectedROIIndex <= numel(frameData(currentIndex).boxes)
            frameData(currentIndex).boxes(selectedROIIndex).ContactID = selectedContactID;
            contactIDField.Value = char(selectedContactID);
            frameData(currentIndex).boxes(selectedROIIndex).Source = appendEditedSuffix(frameData(currentIndex).boxes(selectedROIIndex).Source);
            if selectedROIIndex <= numel(currentROIHandles) && isvalid(currentROIHandles(selectedROIIndex))
                currentROIHandles(selectedROIIndex).Label = makeROILabel(frameData(currentIndex).boxes(selectedROIIndex));
            end
        end
        refreshBoxTable(); updateTextLabels();
    end

    function clearCurrentBoxes()
        answer = uiconfirm(fig, "Remove all boxes from this frame?", "Clear Boxes", "Options", ["Yes", "No"], "DefaultOption", "No");
        if answer ~= "Yes"; return; end
        frameData(currentIndex).boxes = makeEmptyBoxesStruct();
        selectedROIIndex = [];
        refreshDisplay();
    end

    function rerunDetectorOnCurrentFrame()
        if lower(detectorMode) == "none" || isempty(detector)
            uialert(fig, "Detector mode is set to none. No model will run.", "No Model"); return;
        end
        answer = uiconfirm(fig, "Run model again and replace current boxes?", "Run Model", "Options", ["Yes", "No"], "DefaultOption", "No");
        if answer ~= "Yes"; return; end
        frameData(currentIndex).detected = false;
        runDetectorForFrame(currentIndex);
        selectedROIIndex = [];
        refreshDisplay();
    end

    function markFrame(status)
        saveCurrentROIsToMemory();
        frameData(currentIndex).frameStatus = string(status);
        frameData(currentIndex).reviewed = string(status) ~= "unreviewed";
        updateTextLabels();
    end

    function saveCurrentFrameOnly()
        saveCurrentROIsToMemory();
        frameData(currentIndex).reviewed = true;
        exportOneFrame(currentIndex);
        uialert(fig, "Current frame exported.", "Saved");
        updateTextLabels();
    end

    function saveAndNext()
        saveCurrentROIsToMemory();
        frameData(currentIndex).reviewed = true;
        exportOneFrame(currentIndex);
        if currentIndex < numImages
            loadFrame(currentIndex + 1);
        else
            updateTextLabels(); uialert(fig, "Last frame reached.", "Done");
        end
    end

    function goPrevious()
        if currentIndex <= 1; return; end
        loadFrame(currentIndex - 1);
    end

    function goNext()
        if currentIndex >= numImages; return; end
        loadFrame(currentIndex + 1);
    end

    function goToFrame()
        saveCurrentROIsToMemory();
        requestedIndex = round(jumpIndexField.Value);
        if requestedIndex < 1 || requestedIndex > numImages
            uialert(fig, sprintf("Frame index must be between 1 and %d.", numImages), "Invalid Frame Index"); return;
        end
        loadFrame(requestedIndex);
    end

    function saveCurrentROIsToMemory()
        if isempty(currentROIHandles); return; end
        boxes = frameData(currentIndex).boxes;
        for j = 1:min(numel(currentROIHandles), numel(boxes))
            if isvalid(currentROIHandles(j))
                boxes(j).Position = currentROIHandles(j).Position;
            end
        end
        frameData(currentIndex).boxes = boxes;
    end

    function deleteCurrentROIHandles()
        if isempty(currentROIHandles); return; end
        for j = 1:numel(currentROIHandles)
            if isvalid(currentROIHandles(j)); delete(currentROIHandles(j)); end
        end
        currentROIHandles = images.roi.Rectangle.empty;
    end

    function reassignObjectIDsIfMissing()
        for j = 1:numel(frameData(currentIndex).boxes)
            if string(frameData(currentIndex).boxes(j).ObjectID) == ""
                frameData(currentIndex).boxes(j).ObjectID = string(j);
            end
        end
    end

    function registerContactID(contactID)
        contactID = strip(string(contactID));
        if contactID == "" || contactID == "<none>"; return; end
        if ~any(knownContactIDs == contactID)
            knownContactIDs(end+1,1) = contactID;
            updateContactIDDropdown();
        end
    end

    function updateContactIDDropdown()
        if isempty(knownContactIDs)
            contactIDDropDown.Items = {'<none>'}; contactIDDropDown.Value = '<none>'; return;
        end
        items = ["<none>"; knownContactIDs];
        contactIDDropDown.Items = cellstr(items);
        if ~any(string(contactIDDropDown.Value) == items); contactIDDropDown.Value = '<none>'; end
    end

    function showContactIDSummary()
        saveCurrentROIsToMemory();
        summaryText = "Known ContactIDs:" + newline;
        if isempty(knownContactIDs)
            summaryText = summaryText + "None";
        else
            for c = 1:numel(knownContactIDs)
                cid = knownContactIDs(c);
                count = countContactIDOccurrences(cid);
                summaryText = summaryText + sprintf("%s : %d boxes\n", cid, count);
            end
        end
        uialert(fig, summaryText, "ContactID Summary");
    end

    function count = countContactIDOccurrences(contactID)
        count = 0;
        for fi = 1:numImages
            boxes = frameData(fi).boxes;
            for bi = 1:numel(boxes)
                if string(boxes(bi).ContactID) == string(contactID)
                    count = count + 1;
                end
            end
        end
    end

%% ========================================================================
% EXPORT FUNCTIONS
% ========================================================================

    function exportAllResults()
        saveCurrentROIsToMemory();
        answer = uiconfirm(fig, "Export all frames to CSV, crops, pixels, and annotated images?", "Export Results", "Options", ["Yes", "No"], "DefaultOption", "Yes");
        if answer ~= "Yes"; return; end
        allResults = table();
        for idx = 1:numImages
            T = exportOneFrame(idx);
            allResults = [allResults; T]; %#ok<AGROW>
        end
        csvPath = fullfile(outputDir, "reviewed_detections_all.csv");
        writetable(allResults, csvPath);
        save(fullfile(outputDir, "reviewed_frameData.mat"), "frameData", "knownContactIDs", "detectorMode", "pretrainedDetectorName", "customModelPath", "detectorDescription", "targetClasses", "manualLabels", "boxColorMode", "defaultBoxColor", "labelColorMap", "sourceColorMap");
        uialert(fig, sprintf("Export complete.\n\nCSV:\n%s", csvPath), "Export Complete");
        fprintf("\nExport complete.\nCSV saved to:\n%s\n", csvPath);
    end

    function T = exportOneFrame(idx)
        imgPath = frameData(idx).imagePath;
        I = imread(imgPath);
        [imgH, imgW, ~] = size(I);
        boxes = frameData(idx).boxes;
        [~, baseName, ~] = fileparts(imgPath);
        uniqueBaseName = sprintf("%06d_%s", idx, baseName);
        annotatedFile = fullfile(annotatedDir, uniqueBaseName + "_reviewed.png");
        annotated = I;
        T = table();

        if ~isempty(boxes)
            for j = 1:numel(boxes)
                pos = boxes(j).Position;
                x1 = max(1, round(pos(1)));
                y1 = max(1, round(pos(2)));
                x2 = min(imgW, round(pos(1) + pos(3) - 1));
                y2 = min(imgH, round(pos(2) + pos(4) - 1));
                finalW = x2 - x1 + 1;
                finalH = y2 - y1 + 1;
                if finalW <= 1 || finalH <= 1; continue; end

                cleanBox = [x1, y1, finalW, finalH];

                if isnan(boxes(j).Confidence)
                    confText = "manual";
                else
                    confText = compose("%.2f", boxes(j).Confidence);
                end

                labelText = makeExportLabelText(boxes(j), confText);
                boxColor = getBoxColor(boxes(j));

                annotated = insertObjectAnnotation(annotated, "rectangle", cleanBox, labelText, "Color", uint8(boxColor));

                objectCrop = I(y1:y2, x1:x2, :);
                [X, Y] = meshgrid(x1:x2, y1:y2);
                pixelCoords = [X(:), Y(:)];
                safeLabel = makeSafeFilename(boxes(j).Label);
                cropFile = fullfile(cropDir, uniqueBaseName + "_object_" + j + "_" + safeLabel + ".png");
                pixelFile = fullfile(pixelDir, uniqueBaseName + "_object_" + j + "_pixels.mat");
                imwrite(objectCrop, cropFile);

                areaPixels = finalW * finalH;
                sizeCategory = classifyObjectSize(finalW, finalH);
                centerX = x1 + finalW / 2;
                centerY = y1 + finalH / 2;
                normCenterX = centerX / imgW;
                normCenterY = centerY / imgH;
                normWidth   = finalW / imgW;
                normHeight  = finalH / imgH;

                save(pixelFile, "pixelCoords", "x1", "y1", "x2", "y2", "finalW", "finalH", "areaPixels", "centerX", "centerY", "normCenterX", "normCenterY", "normWidth", "normHeight", "objectCrop");

                row = table(string(baseName), string(imgPath), idx, string(boxes(j).ObjectID), string(boxes(j).ContactID), string(boxes(j).Label), boxes(j).Confidence, string(boxes(j).Source), string(frameData(idx).frameStatus), logical(frameData(idx).reviewed), x1, y1, x2, y2, finalW, finalH, areaPixels, string(sizeCategory), centerX, centerY, normCenterX, normCenterY, normWidth, normHeight, string(cropFile), string(pixelFile), imgW, imgH, string(annotatedFile), string(detectorDescription), string(boxColorMode), double(boxColor(1)), double(boxColor(2)), double(boxColor(3)), 'VariableNames', {'Frame','FullPath','FrameIndex','ObjectID','ContactID','Label','Confidence','Source','FrameStatus','Reviewed','X1','Y1','X2','Y2','Width','Height','AreaPixels','SizeCategory','CenterX','CenterY','NormCenterX','NormCenterY','NormWidth','NormHeight','CropFile','PixelFile','ImageWidth','ImageHeight','AnnotatedImage','DetectorDescription','BoxColorMode','BoxColorR','BoxColorG','BoxColorB'});
                T = [T; row]; %#ok<AGROW>
            end
        end

        imwrite(annotated, annotatedFile);

        if isempty(T) && exportEmptyFrameRows
            T = table(string(baseName), string(imgPath), idx, string(""), string(""), string("none"), NaN, string("none"), string(frameData(idx).frameStatus), logical(frameData(idx).reviewed), NaN, NaN, NaN, NaN, NaN, NaN, NaN, string("none"), NaN, NaN, NaN, NaN, NaN, NaN, string(""), string(""), imgW, imgH, string(annotatedFile), string(detectorDescription), string(boxColorMode), NaN, NaN, NaN, 'VariableNames', {'Frame','FullPath','FrameIndex','ObjectID','ContactID','Label','Confidence','Source','FrameStatus','Reviewed','X1','Y1','X2','Y2','Width','Height','AreaPixels','SizeCategory','CenterX','CenterY','NormCenterX','NormCenterY','NormWidth','NormHeight','CropFile','PixelFile','ImageWidth','ImageHeight','AnnotatedImage','DetectorDescription','BoxColorMode','BoxColorR','BoxColorG','BoxColorB'});
        end

        perFrameCsv = fullfile(outputDir, uniqueBaseName + "_reviewed.csv");
        writetable(T, perFrameCsv);
    end

%% ========================================================================
% HELPER FUNCTIONS
% ========================================================================

    function files = findImagesRecursive(rootDir)
        imageExts = [".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"];
        listing = dir(fullfile(rootDir, "**", "*"));
        files = strings(0,1);
        for ii = 1:numel(listing)
            if listing(ii).isdir; continue; end
            [~, ~, ext] = fileparts(listing(ii).name);
            ext = lower(string(ext));
            if ismember(ext, imageExts)
                files(end+1,1) = string(fullfile(listing(ii).folder, listing(ii).name)); %#ok<AGROW>
            end
        end
    end

    function boxes = makeEmptyBoxesStruct()
        boxes = struct("ObjectID", {}, "ContactID", {}, "Label", {}, "Confidence", {}, "Position", {}, "Source", {});
    end

    function out = appendEditedSuffix(sourceText)
        out = string(sourceText);
        if ~contains(out, "_edited"); out = out + "_edited"; end
    end

    function label = makeROILabel(box)
        label = char(string(box.Label));
        cid = strip(string(box.ContactID));
        if cid ~= ""; label = label + " | " + char(cid); end
    end

    function labelText = makeExportLabelText(box, confText)
        cid = strip(string(box.ContactID));
        if cid == ""
            labelText = string(box.Label) + " " + confText;
        else
            labelText = string(box.Label) + " [" + cid + "] " + confText;
        end
    end


    function c = getBoxColor(box)
        mode = lower(string(boxColorMode));
        switch mode
            case "label"
                key = char(string(box.Label));
                if isKey(labelColorMap, key)
                    c = labelColorMap(key);
                else
                    c = defaultBoxColor;
                end
            case "source"
                key = char(string(box.Source));
                if isKey(sourceColorMap, key)
                    c = sourceColorMap(key);
                else
                    c = defaultBoxColor;
                end
            case "contactid"
                cid = strip(string(box.ContactID));
                if cid == ""
                    c = defaultBoxColor;
                else
                    c = deterministicColorFromString(cid, contactIDColorSeed);
                end
            case "single"
                c = defaultBoxColor;
            otherwise
                c = defaultBoxColor;
        end
        c = uint8(c);
    end

    function c = deterministicColorFromString(strValue, seed)
        s = char(string(strValue));
        if isempty(s)
            c = defaultBoxColor;
            return;
        end
        hashValue = seed;
        for kk = 1:numel(s)
            hashValue = mod(hashValue * 31 + double(s(kk)), 9973);
        end
        hue = mod(hashValue, 360) / 360;
        rgb = hsv2rgb([hue 0.75 1.00]);
        c = round(rgb * 255);
    end

    function sizeCategory = classifyObjectSize(widthPixels, heightPixels)
        areaPixels = widthPixels * heightPixels;
        if areaPixels < 32 * 32
            sizeCategory = "tiny";
        elseif areaPixels < 96 * 96
            sizeCategory = "small";
        elseif areaPixels < 224 * 224
            sizeCategory = "medium";
        else
            sizeCategory = "large";
        end
    end

    function safeName = makeSafeFilename(label)
        safeName = string(label);
        safeName = replace(safeName, " ", "_");
        safeName = replace(safeName, "/", "_");
        safeName = replace(safeName, "\", "_");
        safeName = replace(safeName, ":", "_");
        safeName = replace(safeName, "*", "_");
        safeName = replace(safeName, "?", "_");
        safeName = replace(safeName, """", "_");
        safeName = replace(safeName, "<", "_");
        safeName = replace(safeName, ">", "_");
        safeName = replace(safeName, "|", "_");
    end
end
