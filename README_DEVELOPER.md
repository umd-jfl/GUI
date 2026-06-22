# MATLAB Maritime Labeling, Object Detection, and Tracking GUI — Developer Documentation

## 1. Overview

`maritime_label_detect_track_gui.m` is a MATLAB GUI for human-in-the-loop labeling, object detection review, and simple object tracking across image frames.

The GUI supports three major tasks:

1. **Labeling**: users can manually add bounding boxes, assign labels, and export reviewed annotations.
2. **Object Detection**: the GUI can run no detector, a pretrained MATLAB YOLOv4 detector, or a custom MATLAB detector.
3. **Tracking**: users can assign a persistent `ContactID` to the same object across multiple frames.

The script is intended for maritime image datasets such as LaRS, SeaShips, drone imagery, harbor camera frames, or other image sequences.

---

## 2. Intended Workflow

```text
Open GUI
    ↓
Load images recursively from input folder
    ↓
Optional model detection produces initial boxes
    ↓
User reviews each frame
    ↓
User adds, deletes, resizes, relabels boxes
    ↓
User assigns ContactID for tracking same object across frames
    ↓
User marks frame status
    ↓
User saves/export results
```

---

## 3. Key Concepts

### ObjectID

`ObjectID` is a user-editable identifier for an object within a single frame. It is local to the frame.

Example:

```text
Frame 10:
ObjectID 1 = boat
ObjectID 2 = buoy
ObjectID 3 = ship
```

The GUI allows manual editing of `ObjectID` in the table. `ObjectID` is not automatically overwritten after deletion.

### ContactID

`ContactID` is a persistent tracking identifier used to link the same object across multiple frames.

Example:

```text
Frame 1: ObjectID = 1, ContactID = V001
Frame 2: ObjectID = 2, ContactID = V001
Frame 3: ObjectID = 1, ContactID = V001
```

This means the object appears in different frames but is considered the same tracked contact.

Important behavior:

- Users can type a new `ContactID`.
- Users can reuse existing ContactIDs from a dropdown.
- The GUI stores known ContactIDs in `knownContactIDs`.
- Adding a new ContactID does not overwrite the previous list.

### Label

`Label` is the semantic category assigned to the object, such as `boat`, `ship`, `submarine`, `buoy`, or `unknown`.

---

## 4. User Settings Section

The top of the script contains the settings most users/developers should modify.

### `inputDir`

```matlab
inputDir = fullfile("lars_v1.0.0_images", "val", "images");
```

Folder containing images. The script searches recursively.

### `outputDir`

```matlab
outputDir = "LaRS_Label_Detect_Track_Output";
```

Folder where all outputs are saved.

### `detectorMode`

```matlab
detectorMode = "pretrained";
```

Accepted values:

```text
none
pretrained
custom
```

- `none`: no model is used; manual-only labeling.
- `pretrained`: uses MATLAB pretrained YOLOv4.
- `custom`: loads a detector from a `.mat` file.

### `pretrainedDetectorName`

```matlab
pretrainedDetectorName = "tiny-yolov4-coco";
```

Common options are `tiny-yolov4-coco` and `csp-darknet53-coco`.

### `customModelPath`

```matlab
customModelPath = fullfile("models", "maritimeDetector.mat");
```

The `.mat` file should contain one of these variables:

```text
detector
trainedDetector
maritimeDetector
```

### `confidenceThreshold`

```matlab
confidenceThreshold = 0.25;
```

Controls minimum confidence for model detections.

### `keepAllDetectedClasses` and `targetClasses`

If `keepAllDetectedClasses = false`, the GUI keeps only classes listed in `targetClasses`.

```matlab
targetClasses = [
    "boat"
    "airplane"
    "bird"
];
```

Adding a class here does not teach the model to detect it; it only filters existing model predictions.

### `manualLabels`

Dropdown labels available for manual labeling.

### `startFrameIndex`

Controls the first frame shown when the GUI opens.

### `maxImagesToLoad`

Limits image count for testing. Use `Inf` to load all images.

### `exportEmptyFrameRows`

When true, frames with no boxes still export a CSV row. This records negative/no-object frames.

---

## 5. Output Folder Structure

```text
LaRS_Label_Detect_Track_Output/
├── reviewed_annotated/
├── reviewed_crops/
├── reviewed_pixels/
├── reviewed_detections_all.csv
├── reviewed_frameData.mat
└── per-frame CSV files
```

### `reviewed_annotated`

Final annotated images with reviewed boxes and labels.

### `reviewed_crops`

Cropped object images for every exported bounding box.

### `reviewed_pixels`

`.mat` files with pixel coordinates and crop data for every object.

### `reviewed_detections_all.csv`

Combined CSV containing all reviewed frames.

### `reviewed_frameData.mat`

Saved internal GUI state for debugging or future reuse.

---

## 6. Internal Data Model

The main state variable is `frameData`.

Each image has:

```matlab
frameData(i).imagePath
frameData(i).detected
frameData(i).reviewed
frameData(i).frameStatus
frameData(i).boxes
```

Each box has:

```matlab
ObjectID
ContactID
Label
Confidence
Position
Source
```

`Position` uses MATLAB box format:

```matlab
[x, y, width, height]
```

---

## 7. GUI Controls

### Go To Frame

Jumps to a chosen frame index.

### Previous / Next

Moves through images.

### Mark Good / Mark Bad / Mark Unreviewed

Sets frame review status.

### Add Box

Lets the user draw a new rectangle.

### Delete Selected

Deletes selected box.

### Apply Label

Applies dropdown label to selected box.

### Apply ContactID

Applies typed ContactID to selected box.

### Use Existing ID

Applies an already-known ContactID to selected box.

### Run/Reload Model

Runs detector again on current frame and replaces existing boxes.

### Clear Boxes

Removes all boxes from current frame.

### Save Current Frame

Exports one frame.

### Save && Next

Exports current frame and moves to next frame.

### Export All Results

Exports all frames.

### Show ContactID Summary

Shows known ContactIDs and occurrence counts.

---

## 8. Function-by-Function Explanation

### `loadFrame(index)`

Loads an image, runs detector if needed, and refreshes display.

### `runDetectorForFrame(index)`

Runs model detection unless `detectorMode = none`. Stores detections in `frameData(index).boxes`.

### `refreshDisplay()`

Redraws the image and editable ROI boxes.

### `updateTextLabels()`

Updates frame number, filename, review status, progress, and ContactID count.

### `refreshBoxTable()`

Updates the table from current `frameData` boxes.

### `roiClicked(src)`

Selects a clicked ROI and updates label/contact controls.

### `roiMoved(src)`

Stores new ROI position and marks source as edited.

### `highlightSelectedROI()`

Increases selected ROI line width.

### `tableSelectionChanged(event)`

Links selected table row to selected ROI.

### `tableCellEdited(event)`

Handles edits to ObjectID, ContactID, and Label.

### `addBox()`

Creates a new manual box with selected label and typed ContactID.

### `deleteSelectedBox()`

Deletes selected box without overwriting other ObjectIDs.

### `applySelectedLabel()`

Applies dropdown label to selected box.

### `applySelectedContactID()`

Applies typed ContactID to selected box and registers it.

### `useExistingContactID()`

Applies selected known ContactID from dropdown.

### `clearCurrentBoxes()`

Deletes all current-frame boxes.

### `rerunDetectorOnCurrentFrame()`

Runs detector again and replaces boxes.

### `markFrame(status)`

Sets status to `good`, `bad`, or `unreviewed`.

### `saveCurrentFrameOnly()`

Exports one frame.

### `saveAndNext()`

Exports current frame and advances to next frame.

### `goPrevious()` / `goNext()` / `goToFrame()`

Navigation functions.

### `saveCurrentROIsToMemory()`

Copies ROI positions into `frameData`. This preserves manual movement/resizing.

### `registerContactID(contactID)`

Adds new ContactID to known list.

### `updateContactIDDropdown()`

Refreshes ContactID dropdown.

### `showContactIDSummary()`

Displays tracking ID counts.

### `exportOneFrame(idx)`

Exports annotated image, crops, pixel files, and per-frame CSV for one frame.

### `exportAllResults()`

Exports every frame and combined CSV.

---

## 9. Exported CSV Columns

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
```

---

## 10. Tracking Behavior

Tracking is manual. The GUI does not automatically follow objects across frames.

The user assigns the same ContactID to the same object in different frames.

Example:

```text
FrameIndex,ObjectID,ContactID,Label
1,1,V001,boat
2,3,V001,boat
3,2,V001,ship
```

Rows with the same ContactID are treated as the same tracked object.

---

## 11. Empty Frame Export

When `exportEmptyFrameRows = true`, a frame with no boxes still writes a CSV row.

Object fields are blank, `NaN`, or `none`, while frame-level fields remain filled.

This is useful for documenting reviewed negative frames.

---

## 12. Common Modifications

### Use no model

```matlab
detectorMode = "none";
```

### Use pretrained model

```matlab
detectorMode = "pretrained";
pretrainedDetectorName = "tiny-yolov4-coco";
```

### Use custom model

```matlab
detectorMode = "custom";
customModelPath = fullfile("models", "maritimeDetector.mat");
```

### Start from frame 100

```matlab
startFrameIndex = 100;
```

### Load all images

```matlab
maxImagesToLoad = Inf;
```

### Add labels

Edit the `manualLabels` list.

---

## 13. Limitations

- Tracking is manual, not automatic.
- Pretrained COCO YOLO cannot detect custom maritime categories unless trained for them.
- Rectangular bounding boxes only.
- No session reload from CSV yet.
- No YOLO/COCO JSON export yet.

---

## 14. Suggested Future Improvements

- typed custom labels directly in GUI
- GUI-configurable target class filter
- save/load review sessions
- export to YOLO label format
- export to COCO JSON
- automatic tracking via IoU or optical flow
- video support
- rotated bounding boxes
- segmentation mask support
- keyboard shortcuts
- undo/redo

---

## 15. Summary

This GUI is a MATLAB-based human-in-the-loop tool for maritime object labeling, detection review, and manual tracking.

The most important concepts are:

- `ObjectID`: local per-frame object identifier
- `ContactID`: persistent cross-frame tracking identifier
- `Label`: object category
- `frameData`: internal state for all images and boxes

The key functions are:

```text
runDetectorForFrame
refreshDisplay
saveCurrentROIsToMemory
tableCellEdited
registerContactID
exportOneFrame
exportAllResults
```
