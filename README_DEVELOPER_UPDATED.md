# MATLAB Maritime Labeling, Object Detection, Tracking, Color Export, and CSV Redraw GUI — Developer README

## 1. Overview

This project contains a MATLAB-based human-in-the-loop annotation and review workflow for maritime imagery. The system is designed for three main tasks:

1. Manual labeling
2. Object detection review
3. Manual object tracking across frames

The main GUI allows a user to load images, run a detector if available, edit bounding boxes, assign labels, assign tracking IDs, save reviewed annotations, and export results. A separate redraw script can later read the exported CSV files and reconstruct the annotated images from the original image files.

The current package contains two major MATLAB scripts:

```text
maritime_label_detect_track_gui.m
redraw_boxes_from_review_csv.m
```

`maritime_label_detect_track_gui.m` is used during review and annotation.  
`redraw_boxes_from_review_csv.m` is used after export to recreate annotated images from saved CSV data.

---

## 2. Main Purpose of the GUI

The GUI is meant for:

- labeling objects in maritime images,
- reviewing automatic object detection results,
- correcting wrong bounding boxes,
- adding missed objects,
- deleting false detections,
- assigning object labels,
- assigning local object IDs,
- assigning persistent tracking IDs,
- exporting reviewed annotations,
- and recreating reviewed images later from CSV files.

The GUI is especially useful when pretrained YOLO detections are incomplete or inaccurate and a human reviewer needs to correct the results before using them for model training, evaluation, or analysis.

---

## 3. Core Capabilities

The GUI currently supports:

```text
Image folder loading
Recursive image search
Start from any frame index
Jump to any frame index
No-model manual labeling mode
Pretrained MATLAB YOLOv4 detection mode
Custom MATLAB detector mode
Editable bounding boxes
Manual box creation
Manual box deletion
Manual box movement and resizing
Editable ObjectID
Editable ContactID
Editable object Label
Reusable ContactID tracking list
ContactID summary display
Good / bad / unreviewed frame status
Empty-frame CSV export
Reviewed annotated image export
Object crop export
Pixel-coordinate MAT export
Per-frame CSV export
Combined CSV export
Predefined saved bounding-box colors
CSV-based annotation redraw
```

---

## 4. Recommended Annotation Concepts

### 4.1 Label

`Label` is the semantic class of the object.

Examples:

```text
boat
ship
submarine
cargo_ship
warship
aircraft_carrier
sailboat
fishing_boat
passenger_ship
airplane
helicopter
bird
buoy
dock
unknown
```

The label may come from the detector or may be manually assigned by the user.

---

### 4.2 ObjectID

`ObjectID` is a local object identifier within one frame.

Example:

```text
Frame 10:
ObjectID 1 = boat
ObjectID 2 = buoy
ObjectID 3 = ship
```

The user can manually edit `ObjectID` in the table.

Important notes:

- `ObjectID` is local to a frame.
- It does not need to remain the same across frames.
- It is useful for distinguishing multiple objects within the same image.
- The GUI does not overwrite manually edited ObjectIDs.

---

### 4.3 ContactID

`ContactID` is a persistent tracking identifier for the same real-world object across multiple frames.

Example:

```text
FrameIndex,ObjectID,ContactID,Label
1,1,V001,boat
2,2,V001,boat
3,1,V001,ship
```

This means the same object is being tracked as `V001` across multiple frames.

Important notes:

- `ContactID` is manually assigned by the user.
- The same ContactID can be reused across frames.
- The GUI keeps a running list of known ContactIDs.
- Adding a new ContactID does not overwrite previous ContactIDs.
- The user can select an existing ContactID from a dropdown and apply it quickly.

---

## 5. Detector Modes

The GUI supports three detector modes.

### 5.1 No-Model Mode

```matlab
detectorMode = "none";
```

In this mode, no automatic detector is used. The GUI loads images with no boxes, and the user manually creates annotations.

Use this when:

- no detector is available,
- the machine does not have pretrained models installed,
- the user wants to manually label everything,
- or the GUI is being tested without model dependencies.

---

### 5.2 Pretrained Detector Mode

```matlab
detectorMode = "pretrained";
pretrainedDetectorName = "tiny-yolov4-coco";
```

This mode loads a MATLAB pretrained YOLOv4 detector.

Common pretrained options:

```matlab
pretrainedDetectorName = "tiny-yolov4-coco";
pretrainedDetectorName = "csp-darknet53-coco";
```

The pretrained COCO model can detect general COCO classes such as:

```text
boat
airplane
bird
person
car
truck
```

However, it cannot automatically detect specialized maritime categories such as:

```text
submarine
warship
cargo_ship
aircraft_carrier
```

unless those classes are part of a custom trained model.

---

### 5.3 Custom Detector Mode

```matlab
detectorMode = "custom";
customModelPath = fullfile("models", "maritimeDetector.mat");
```

This mode loads a custom MATLAB detector from a `.mat` file.

The `.mat` file should contain one of these variable names:

```text
detector
trainedDetector
maritimeDetector
```

The detector must support:

```matlab
detect(detector, I, Threshold=confidenceThreshold)
```

Use this mode after training a custom maritime detector.

---

## 6. User Settings Section

Most project-level changes should be made at the top of `maritime_label_detect_track_gui.m`.

### 6.1 Input Folder

```matlab
inputDir = fullfile("lars_v1.0.0_images", "val", "images");
```

This is the folder containing the images to review.

The GUI searches recursively, so nested folders are allowed.

Example absolute path:

```matlab
inputDir = "C:\Users\Name\Desktop\Dataset\images";
```

---

### 6.2 Output Folder

```matlab
outputDir = "LaRS_Label_Detect_Track_Output";
```

This folder stores all exported results.

The GUI automatically creates the output folder and its subfolders.

---

### 6.3 Start Frame Index

```matlab
startFrameIndex = 1;
```

This controls which frame the GUI opens first.

Example:

```matlab
startFrameIndex = 75;
```

The GUI will begin at frame 75.

The GUI also includes a `Go To Frame` field so the user can jump to any frame while reviewing.

---

### 6.4 Maximum Images to Load

```matlab
maxImagesToLoad = 200;
```

This limits how many images are loaded.

For all images:

```matlab
maxImagesToLoad = Inf;
```

This is useful because large datasets may take longer to process.

---

### 6.5 Export Empty Frame Rows

```matlab
exportEmptyFrameRows = true;
```

If a frame has no boxes, the GUI still exports a CSV row with frame-level information and blank object-level information.

This is important for documenting negative frames or no-object frames.

---

### 6.6 Confidence Threshold

```matlab
confidenceThreshold = 0.25;
```

This controls how confident a model detection must be before it is shown.

Lower value:

```matlab
confidenceThreshold = 0.15;
```

Produces more detections but more false positives.

Higher value:

```matlab
confidenceThreshold = 0.50;
```

Produces fewer detections but more conservative results.

---

### 6.7 Target Classes

```matlab
targetClasses = [
    "boat"
    "airplane"
    "bird"
];
```

If:

```matlab
keepAllDetectedClasses = false;
```

then only detections whose labels are in `targetClasses` are shown.

To show all model detections:

```matlab
keepAllDetectedClasses = true;
```

Important:

Adding a class to `targetClasses` does not teach the model that class. It only filters detections that the model already predicted.

---

### 6.8 Manual Labels

```matlab
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
```

These are the labels available in the GUI dropdown.

To add a new label, add it to this list.

Example:

```matlab
manualLabels = [
    "boat"
    "ship"
    "kayak"
    "dock"
    "buoy"
    "unknown"
];
```

---

## 7. Bounding-Box Color Settings

The GUI allows the user or developer to predefine bounding-box colors for saved annotated images.

This affects exported images, not necessarily the live editable ROI color inside the GUI.

### 7.1 Color Mode

```matlab
boxColorMode = "label";
```

Supported modes:

```text
label
contactID
source
single
```

---

### 7.2 Label-Based Coloring

When:

```matlab
boxColorMode = "label";
```

the saved box color is selected based on object label.

Example:

```matlab
labelColorMap = containers.Map( ...
    {'boat','ship','submarine'}, ...
    {[0 255 255], [255 255 0], [255 0 255]} ...
);
```

Example meaning:

```text
boat      cyan
ship      yellow
submarine magenta
```

To change a label color:

```matlab
labelColorMap('boat') = [0 255 0];
```

---

### 7.3 ContactID-Based Coloring

When:

```matlab
boxColorMode = "contactID";
```

the GUI assigns a deterministic color based on the ContactID.

The same ContactID will receive the same color across frames.

This is useful for tracking because the same object/contact can remain visually consistent.

---

### 7.4 Source-Based Coloring

When:

```matlab
boxColorMode = "source";
```

the saved box color is selected based on where the box came from.

Example sources:

```text
pretrained
custom
manual
pretrained_edited
custom_edited
manual_edited
```

This can help distinguish between original model detections and human-edited boxes.

---

### 7.5 Single-Color Mode

When:

```matlab
boxColorMode = "single";
```

all boxes use:

```matlab
defaultBoxColor = [255 255 0];
```

This is useful when a clean, consistent visual style is preferred.

---

### 7.6 Saved Color Metadata

The exported CSV includes:

```text
BoxColorMode
BoxColorR
BoxColorG
BoxColorB
```

These columns allow the redraw script to recreate the same box colors later.

---

## 8. GUI Layout

The GUI has two main panels.

### 8.1 Left Panel

The left panel displays:

- the current image,
- editable bounding boxes,
- ROI labels,
- and a frame status message.

Bounding boxes can be moved or resized directly on the image.

---

### 8.2 Right Panel

The right panel contains:

```text
Detector description
Frame information
Filename
Frame status
Go To Frame
Previous / Next
Mark Good
Mark Bad
Mark Unreviewed
Add Box
Delete Selected
Label dropdown
Apply Label
ContactID text field
Apply ContactID
Existing ContactID dropdown
Use Existing ID
Saved Box Color Mode dropdown
Run/Reload Model
Clear Boxes
Save Current Frame
Export All Results
Help text
Bounding-box table
Progress text
Save && Next
Show ContactID Summary
```

---

## 9. Bounding-Box Table

The table columns are:

```text
ObjectID
ContactID
Label
Confidence
X
Y
W
H
Source
```

Editable columns:

```text
ObjectID
ContactID
Label
```

The user can directly edit the ID fields and labels in the table.

---

## 10. ContactID Summary

The GUI includes a `Show ContactID Summary` button.

The improved summary should show:

```text
ContactID
Number of boxes
Frames where it appears
First frame
Last frame
Labels used
```

Example:

```text
V001
  Boxes: 12
  Frames: 1-6, 9, 12-14
  First frame: 1
  Last frame: 14
  Labels: boat, ship

V002
  Boxes: 5
  Frames: 3, 4, 7
  First frame: 3
  Last frame: 7
  Labels: buoy
```

This is more useful than only showing the box count, because tracking requires knowing where a ContactID appears.

Implementation note:

If using `sprintf`, use `%s` for text fields such as frame lists and label lists, and `%d` only for numeric fields.

Example:

```matlab
summaryText = summaryText + sprintf("  Frames: %s\n", char(info.FrameListText));
summaryText = summaryText + sprintf("  Labels: %s\n\n", char(info.LabelListText));
```

---

## 11. Output Folder Structure

The GUI exports to:

```text
LaRS_Label_Detect_Track_Output/
├── reviewed_annotated/
├── reviewed_crops/
├── reviewed_pixels/
├── reviewed_detections_all.csv
├── reviewed_frameData.mat
└── per-frame reviewed CSV files
```

---

### 11.1 reviewed_annotated

Contains reviewed images with final boxes and labels drawn.

---

### 11.2 reviewed_crops

Contains cropped object images.

Each crop corresponds to one bounding box.

---

### 11.3 reviewed_pixels

Contains `.mat` files with pixel coordinates and crop data.

Each file contains information such as:

```text
pixelCoords
x1
y1
x2
y2
finalW
finalH
areaPixels
centerX
centerY
normCenterX
normCenterY
normWidth
normHeight
objectCrop
```

---

### 11.4 reviewed_detections_all.csv

Combined CSV containing all reviewed frames.

---

### 11.5 reviewed_frameData.mat

Stores internal MATLAB state, including:

```text
frameData
knownContactIDs
detectorMode
detector settings
targetClasses
manualLabels
box color settings
```

---

## 12. Exported CSV Columns

The combined and per-frame CSV files include:

```text
Frame
FullPath
FrameIndex
ObjectID
ContactID
Label
Confidence
Source
FrameStatus
Reviewed
X1
Y1
X2
Y2
Width
Height
AreaPixels
SizeCategory
CenterX
CenterY
NormCenterX
NormCenterY
NormWidth
NormHeight
CropFile
PixelFile
ImageWidth
ImageHeight
AnnotatedImage
DetectorDescription
BoxColorMode
BoxColorR
BoxColorG
BoxColorB
```

---

## 13. Empty Frame Export

When a frame has no bounding boxes and:

```matlab
exportEmptyFrameRows = true;
```

the GUI exports a CSV row with frame information but no object information.

Object-related fields are blank, `none`, or `NaN`.

This allows downstream scripts to know that the frame was reviewed or processed even though no object was labeled.

---

## 14. Main GUI Functions

### 14.1 loadFrame(index)

Loads one frame into the GUI.

Responsibilities:

- save current ROI edits,
- update `currentIndex`,
- read the image,
- run detection if needed,
- refresh the GUI display.

Modification approach:

If the source of frames changes, this is one of the first functions to update. For example, a developer could replace `imread` with another frame-loading method, such as a video frame reader, database image loader, or streaming source reader.

---

### 14.2 runDetectorForFrame(index)

Runs the selected detector on a frame.

Current behavior:

- if detector mode is `none`, no boxes are created,
- otherwise calls MATLAB `detect`,
- filters classes using `targetClasses`,
- stores results in `frameData(index).boxes`.

Modification approach:

If a different model or detector API is introduced, adapt this function so its output is converted into the GUI’s standard internal box format:

```matlab
ObjectID
ContactID
Label
Confidence
Position
Source
```

This function should remain the bridge between model-specific detection output and the GUI’s common annotation structure.

---

### 14.3 refreshDisplay()

Redraws the current image and all editable bounding boxes.

Current behavior:

- clears the axes,
- displays the current image,
- creates one `drawrectangle` ROI per box,
- labels each ROI with label and ContactID.

Modification approach:

If the visual display needs to change, this is the primary place to edit. For example, a developer could add confidence text, change ROI color, support polygon objects, show additional metadata, or visualize masks.

---

### 14.4 refreshBoxTable()

Updates the right-side table from `frameData`.

Current behavior:

- displays ObjectID, ContactID, Label, Confidence, coordinates, and source,
- allows editing ObjectID, ContactID, and Label.

Modification approach:

If new fields are added to boxes, add matching columns here. For example, a future developer may add reviewer notes, occlusion flags, visibility scores, object type, or quality flags.

---

### 14.5 tableCellEdited(event)

Handles table edits.

Current editable fields:

```text
ObjectID
ContactID
Label
```

Modification approach:

If additional table columns become editable, this function should be extended with new cases. It is also the correct place to add validation rules, such as label validation, ContactID naming rules, or coordinate range checking.

---

### 14.6 addBox()

Allows the user to manually draw a new bounding box.

Current behavior:

- uses the selected dropdown label,
- uses the typed ContactID,
- sets Confidence to `NaN`,
- sets Source to `manual`.

Modification approach:

If new manually created boxes need additional metadata, initialize those fields here. This is also the correct place to add automatic ID generation, a popup form after box creation, or default box attributes.

---

### 14.7 deleteSelectedBox()

Deletes the selected bounding box.

Current behavior:

- removes the selected box from `frameData`,
- refreshes display,
- does not overwrite existing ObjectIDs.

Modification approach:

If deletion needs to be reversible, this function should be connected to an undo stack. If deleted objects need to be audited, this is where deleted box records can be logged before removal.

---

### 14.8 applySelectedLabel()

Applies the dropdown label to the selected box.

Modification approach:

If labels become user-typed or externally loaded, update this function so it accepts those new label sources. If label changes should trigger color updates or validation warnings, this function is the correct location.

---

### 14.9 applySelectedContactID()

Applies the typed ContactID to the selected box.

Current behavior:

- updates the box ContactID,
- registers the ID in `knownContactIDs`,
- refreshes the GUI.

Modification approach:

This function is the central place for contact-tracking rules. If future requirements include duplicate warnings, contact consistency checks, auto-suggestions, or metadata updates, add that logic here.

---

### 14.10 useExistingContactID()

Applies an existing ContactID from the dropdown to the selected box.

This is the main convenience feature for manual tracking.

Modification approach:

If the ContactID list becomes large, replace the dropdown with a searchable table or list. If users need to jump to where a ContactID appears, connect this function or related UI controls to the ContactID summary data.

---

### 14.11 registerContactID(contactID)

Adds a ContactID to the known ContactID list.

Current behavior:

- ignores blank values,
- avoids duplicates,
- updates the dropdown.

Modification approach:

If ContactIDs need more metadata, replace `knownContactIDs` with a table or struct array. For example, a future version could store first frame, last frame, primary label, confidence, or notes for each ContactID.

---

### 14.12 showContactIDSummary()

Displays a summary of tracked ContactIDs.

Recommended current behavior:

- show ContactID,
- show number of boxes,
- show frame list,
- show first and last frame,
- show labels used.

Modification approach:

If the summary becomes too long for a popup, replace the popup with a dedicated summary window or table. This would make it easier to sort, search, export, and jump to frames associated with a ContactID.

---

### 14.13 exportOneFrame(idx)

Exports one frame.

Current behavior:

- saves an annotated image,
- saves object crops,
- saves pixel-coordinate `.mat` files,
- writes a per-frame CSV,
- writes empty-frame rows when applicable,
- saves color metadata.

Modification approach:

If additional output formats are needed, this function should produce a common per-frame annotation structure first, then write that structure using separate writer functions. This keeps export logic clean and prevents the GUI’s internal data model from being tied to one file format.

---

### 14.14 exportAllResults()

Exports all frames.

Current behavior:

- calls `exportOneFrame` for each loaded frame,
- combines all rows,
- writes `reviewed_detections_all.csv`,
- saves `reviewed_frameData.mat`.

Modification approach:

If exporting large datasets, avoid repeatedly concatenating tables in memory. Instead, write results incrementally or collect data in a preallocated structure. If multiple output formats are needed, this function should coordinate the export workflow and call format-specific writer functions.

---

### 14.15 getBoxColor(box)

Determines the saved bounding-box color.

Current supported color modes:

```text
label
contactID
source
single
```

Modification approach:

If additional color logic is needed, add a new mode here and expose it in the GUI dropdown. For example, color could be based on confidence, frame status, reviewer, object size, source model, or annotation quality.

---

### 14.16 makeExportLabelText(box, confText)

Builds the text shown on exported annotated images.

Current text can include:

```text
Label
ObjectID
ContactID
Confidence or manual marker
```

Modification approach:

If exported annotation text needs to be customized, this function should be updated. For missing fields, the function should skip unavailable values rather than failing or displaying empty placeholders.

---

## 15. Redraw Script

The redraw script is:

```text
redraw_boxes_from_review_csv.m
```

It reads saved CSV files and reapplies boxes to the original images.

---

### 15.1 Redraw Script Purpose

Use this script when:

- you want to recreate annotated images from exported annotation files,
- you changed color rules and want new images,
- you lost the reviewed annotated images but still have the CSV,
- you want report-ready images,
- or you want to verify exported annotations.

---

### 15.2 Basic Redraw Use

At the top of the script, set:

```matlab
csvPath = fullfile("LaRS_Label_Detect_Track_Output", "reviewed_detections_all.csv");
redrawOutputDir = fullfile("LaRS_Label_Detect_Track_Output", "redrawn_from_csv");
```

Then run:

```matlab
redraw_boxes_from_review_csv
```

---

### 15.3 Redraw Color Options

The redraw script can either use saved colors from the CSV:

```matlab
useSavedCsvColors = true;
```

or recompute colors:

```matlab
useSavedCsvColors = false;
redrawBoxColorMode = "contactID";
```

Supported redraw color modes:

```text
label
contactID
single
```

---

### 15.4 Redraw Annotation Text

The redraw script should build annotation text field-by-field.

It should display available fields and ignore missing fields.

Recommended display fields:

```text
Label
ObjectID
ContactID
Confidence
Source
FrameStatus
```

If a field is missing, blank, `NaN`, or `none`, it should be skipped.

Example:

If the CSV row has:

```text
Label = ship
ObjectID = 2
ContactID = V004
Confidence = NaN
Source = manual
```

The redrawn label should show:

```text
ship | ID:2 | CID:V004 | Source:manual
```

If ContactID is missing:

```text
ship | ID:2 | Source:manual
```

If Label is missing but ObjectID and ContactID exist:

```text
ID:2 | CID:V004
```

The redraw script should not fail just because one field is missing.

---

### 15.5 Redraw Image Path Handling

The redraw script first tries to use:

```text
FullPath
```

from the CSV.

If the original image path no longer exists, the script can use:

```matlab
fallbackImageFolder = "C:\NewDatasetLocation\images";
```

It then searches for images by frame name.

---

## 16. General Approach for Supporting Additional Export Formats

The current system exports CSV files, annotated images, crops, and `.mat` pixel files. If future users need additional formats, the recommended approach is not to rewrite the GUI directly for each new format. Instead, separate the export process into two conceptual steps:

```text
Internal reviewed data
    ↓
Common annotation structure
    ↓
Format-specific writer
```

The GUI’s internal reviewed data is stored in `frameData`. The exporter should first convert each reviewed frame into a consistent annotation structure containing frame path, image size, box coordinates, labels, ObjectIDs, ContactIDs, and metadata. Then separate writer functions can convert that common structure into the desired file format.

This approach can support many output types, such as:

```text
CSV tables
JSON files
MAT files
YOLO text labels
COCO-style annotation files
Pascal VOC XML
custom project-specific formats
database rows
spreadsheet reports
```

Recommended developer pattern:

```matlab
annotationData = buildAnnotationData(frameData);
writeCsv(annotationData, outputDir);
writeJson(annotationData, outputDir);
writeMat(annotationData, outputDir);
writeCustomFormat(annotationData, outputDir);
```

This keeps the core GUI independent of any single export format.

---

## 17. General Approach for Supporting Additional Input Sources

The current GUI loads image files from a folder. If future users need other input sources, the recommended approach is to abstract frame loading behind a single function.

Current concept:

```text
imageFiles(index) → imread(imageFiles(index))
```

More general concept:

```text
frameSource + frameIndex → currentImage + frameMetadata
```

A future developer could support:

```text
image folders
video files
image sequences
network folders
camera streams
database image records
cloud-stored images
pre-extracted video frames
```

Recommended developer pattern:

```matlab
[currentImage, frameInfo] = loadFrameFromSource(frameSource, index);
```

Then `loadFrame(index)` can remain mostly the same regardless of where the image comes from.

For example:

- image folder mode reads with `imread`,
- video mode reads with `VideoReader`,
- database mode retrieves image bytes or local cached files,
- stream mode reads the latest frame.

The rest of the GUI should operate on the same `currentImage` and `frameData` structure.

---

## 18. General Approach for Supporting Other Annotation Types

The current GUI uses rectangular bounding boxes. Future projects may require other annotation types.

Potential annotation types include:

```text
rectangular bounding boxes
rotated bounding boxes
polygons
segmentation masks
points
lines
tracks
region groups
```

The recommended approach is to generalize each box record into an annotation record.

Current box fields:

```text
ObjectID
ContactID
Label
Confidence
Position
Source
```

More general annotation fields:

```text
AnnotationID
ContactID
Label
Confidence
GeometryType
GeometryData
Source
Metadata
```

For example:

```text
GeometryType = "bbox"
GeometryData = [x y width height]

GeometryType = "polygon"
GeometryData = [x1 y1; x2 y2; x3 y3; ...]

GeometryType = "mask"
GeometryData = mask file path or binary mask
```

This allows the GUI to evolve without redesigning the entire internal data model.

---

## 19. General Approach for Supporting Additional Tracking Features

The current tracking system is manual. The user assigns ContactIDs to objects across frames.

Future tracking features can be added gradually.

A general tracking workflow could be:

```text
Current frame boxes
    ↓
Previous frame tracked boxes
    ↓
Candidate matching
    ↓
Suggested ContactID
    ↓
User accepts or edits suggestion
```

Candidate matching could be based on:

```text
bounding box overlap
center distance
object label similarity
object size similarity
motion prediction
appearance similarity
optical flow
Kalman filtering
deep feature embeddings
```

The important design principle is that automatic tracking should remain a suggestion system unless the project fully trusts the tracker. For annotation work, the user should still be able to override every ContactID.

Recommended developer pattern:

```matlab
suggestedContactIDs = suggestContactIDs(currentBoxes, previousBoxes, trackingState);
```

Then display the suggestions in the GUI and allow the user to accept or modify them.

---

## 20. Important Limitations

Current limitations:

```text
Tracking is manual, not automatic.
The GUI supports rectangular boxes, not polygons.
The GUI currently uses image files as input.
The GUI does not currently reload previous sessions automatically.
The GUI currently exports CSV as the primary table format.
Pretrained COCO YOLO cannot detect custom maritime categories unless trained.
```

These limitations are not permanent design constraints. The code can be extended by following the generalized approaches described above:

```text
abstract frame loading for new input sources,
convert frameData into a common annotation structure before export,
add format-specific writer functions for new output formats,
generalize box records into annotation records for non-box geometry,
and add optional tracking suggestions while preserving user override.
```
