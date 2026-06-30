"""
maritime_label_detect_track_gui.py

Python maritime labeling, object detection review, and manual tracking GUI.

Main features:
- image-folder review
- start from any frame index
- jump to frame
- no-model / pretrained / custom Ultralytics YOLO modes
- editable bounding boxes
- editable ObjectID, ContactID, and Label
- reusable ContactID tracking list
- ContactID summary with frames, first/last frame, and labels
- saved bounding-box color modes: label, contactID, source, single
- empty-frame CSV export
- per-frame CSV export
- combined CSV export
- reviewed annotated image export
- object crop export
- pixel coordinate .npz export

Run:
    python maritime_label_detect_track_gui.py
"""

from __future__ import annotations

import hashlib
import math
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
import pandas as pd
from PySide6.QtCore import Qt, QRectF, QPointF
from PySide6.QtGui import QAction, QBrush, QColor, QImage, QMouseEvent, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QDoubleSpinBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

try:
    from ultralytics import YOLO
except Exception:  # pragma: no cover
    YOLO = None


# =============================================================================
# USER SETTINGS
# =============================================================================

INPUT_DIR = Path("lars_v1.0.0_images") / "val" / "images"
OUTPUT_DIR = Path("LaRS_Label_Detect_Track_Output_Python")

# Detector modes: "none", "pretrained", "custom"
DETECTOR_MODE = "pretrained"
PRETRAINED_MODEL_NAME = "yolov8n.pt"
CUSTOM_MODEL_PATH = Path("models") / "best.pt"
CONFIDENCE_THRESHOLD = 0.25

KEEP_ALL_DETECTED_CLASSES = False
TARGET_CLASSES = ["boat", "airplane", "bird"]

MANUAL_LABELS = [
    "boat",
    "ship",
    "submarine",
    "cargo_ship",
    "warship",
    "aircraft_carrier",
    "sailboat",
    "fishing_boat",
    "passenger_ship",
    "airplane",
    "helicopter",
    "bird",
    "buoy",
    "dock",
    "unknown",
]
DEFAULT_MANUAL_LABEL = "ship"
DEFAULT_CONTACT_ID = ""

START_FRAME_INDEX = 1  # 1-based index, matching the MATLAB GUI convention
MAX_IMAGES_TO_LOAD = 200  # use None for all images
EXPORT_EMPTY_FRAME_ROWS = True

# Saved annotation color settings.
# Modes: "label", "contactID", "source", "single"
BOX_COLOR_MODE = "label"
DEFAULT_BOX_COLOR = (255, 255, 0)  # RGB yellow

LABEL_COLOR_MAP: Dict[str, Tuple[int, int, int]] = {
    "boat": (0, 255, 255),
    "ship": (255, 255, 0),
    "submarine": (255, 0, 255),
    "cargo_ship": (255, 128, 0),
    "warship": (255, 0, 0),
    "aircraft_carrier": (128, 0, 255),
    "sailboat": (0, 255, 0),
    "fishing_boat": (0, 128, 255),
    "passenger_ship": (128, 255, 0),
    "airplane": (0, 0, 255),
    "helicopter": (128, 128, 255),
    "bird": (0, 255, 128),
    "buoy": (255, 128, 128),
    "dock": (128, 128, 128),
    "unknown": (255, 255, 255),
    "none": (255, 255, 255),
}

SOURCE_COLOR_MAP: Dict[str, Tuple[int, int, int]] = {
    "pretrained": (255, 255, 0),
    "custom": (0, 255, 0),
    "manual": (0, 255, 255),
    "pretrained_edited": (255, 128, 0),
    "custom_edited": (128, 255, 0),
    "manual_edited": (0, 128, 255),
    "none": (255, 255, 255),
}


# =============================================================================
# DATA STRUCTURES
# =============================================================================

@dataclass
class BoxData:
    object_id: str
    contact_id: str
    label: str
    confidence: float
    x: float
    y: float
    w: float
    h: float
    source: str

    def rect(self) -> QRectF:
        return QRectF(self.x, self.y, self.w, self.h)

    def to_xyxy(self, img_w: int, img_h: int) -> Tuple[int, int, int, int]:
        x1 = max(1, int(round(self.x)))
        y1 = max(1, int(round(self.y)))
        x2 = min(img_w, int(round(self.x + self.w - 1)))
        y2 = min(img_h, int(round(self.y + self.h - 1)))
        return x1, y1, x2, y2


@dataclass
class FrameData:
    image_path: Path
    detected: bool = False
    reviewed: bool = False
    frame_status: str = "unreviewed"
    boxes: List[BoxData] = field(default_factory=list)


# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

def find_images_recursive(root: Path) -> List[Path]:
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
    files = [p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in exts]
    return sorted(files)


def safe_name(text: str) -> str:
    bad = '<>:"/\\|?* '
    out = str(text)
    for ch in bad:
        out = out.replace(ch, "_")
    return out


def append_edited_suffix(source: str) -> str:
    source = str(source or "manual")
    return source if source.endswith("_edited") else f"{source}_edited"


def compact_frame_list(frames: List[int]) -> str:
    frames = sorted(set(int(f) for f in frames))
    if not frames:
        return "none"
    ranges: List[str] = []
    start = prev = frames[0]
    for f in frames[1:]:
        if f == prev + 1:
            prev = f
        else:
            ranges.append(str(start) if start == prev else f"{start}-{prev}")
            start = prev = f
    ranges.append(str(start) if start == prev else f"{start}-{prev}")
    return ", ".join(ranges)


def deterministic_color_from_string(text: str) -> Tuple[int, int, int]:
    if not text:
        return DEFAULT_BOX_COLOR
    digest = hashlib.md5(text.encode("utf-8")).hexdigest()
    hue = int(digest[:6], 16) % 360
    hsv = np.uint8([[[hue / 2, 190, 255]]])  # OpenCV hue is 0-179
    bgr = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)[0, 0]
    return int(bgr[2]), int(bgr[1]), int(bgr[0])


def get_box_color(box: BoxData, mode: str) -> Tuple[int, int, int]:
    mode = str(mode).lower()
    if mode == "label":
        return LABEL_COLOR_MAP.get(box.label, DEFAULT_BOX_COLOR)
    if mode == "source":
        return SOURCE_COLOR_MAP.get(box.source, DEFAULT_BOX_COLOR)
    if mode == "contactid":
        return deterministic_color_from_string(box.contact_id) if box.contact_id else DEFAULT_BOX_COLOR
    return DEFAULT_BOX_COLOR


def box_label_text(box: BoxData, include_confidence: bool = True) -> str:
    parts = []
    if box.label and box.label.lower() != "none":
        parts.append(box.label)
    if box.object_id:
        parts.append(f"ID:{box.object_id}")
    if box.contact_id:
        parts.append(f"CID:{box.contact_id}")
    if include_confidence:
        if box.confidence is None or math.isnan(float(box.confidence)):
            parts.append("manual")
        else:
            parts.append(f"{float(box.confidence):.2f}")
    return " | ".join(parts) if parts else "object"


def classify_object_size(w: int, h: int) -> str:
    area = w * h
    if area < 32 * 32:
        return "tiny"
    if area < 96 * 96:
        return "small"
    if area < 224 * 224:
        return "medium"
    return "large"


def cv2_imread_rgb(path: Path) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise FileNotFoundError(f"Could not read image: {path}")
    return cv2.cvtColor(img, cv2.COLOR_BGR2RGB)


def cv2_imwrite_rgb(path: Path, img_rgb: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR))


# =============================================================================
# IMAGE CANVAS
# =============================================================================

class ImageCanvas(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.image: Optional[np.ndarray] = None
        self.boxes: List[BoxData] = []
        self.selected_index: Optional[int] = None
        self.add_mode = False
        self.drag_mode: Optional[str] = None  # "move", "draw", "resize"
        self.drag_start_img = QPointF()
        self.draw_start_img = QPointF()
        self.original_box: Optional[Tuple[float, float, float, float]] = None
        self.on_selection_changed = None
        self.on_boxes_changed = None
        self.setMinimumSize(900, 650)
        self.setMouseTracking(True)

    def set_image_and_boxes(self, image: np.ndarray, boxes: List[BoxData]) -> None:
        self.image = image
        self.boxes = boxes
        self.selected_index = None
        self.add_mode = False
        self.update()

    def image_to_widget_params(self) -> Tuple[float, float, float]:
        if self.image is None:
            return 1.0, 0.0, 0.0
        h, w = self.image.shape[:2]
        scale = min(self.width() / w, self.height() / h)
        xoff = (self.width() - w * scale) / 2
        yoff = (self.height() - h * scale) / 2
        return scale, xoff, yoff

    def image_point_from_widget(self, pos) -> QPointF:
        scale, xoff, yoff = self.image_to_widget_params()
        return QPointF((pos.x() - xoff) / scale, (pos.y() - yoff) / scale)

    def widget_rect_from_box(self, box: BoxData) -> QRectF:
        scale, xoff, yoff = self.image_to_widget_params()
        return QRectF(xoff + box.x * scale, yoff + box.y * scale, box.w * scale, box.h * scale)

    def paintEvent(self, event):  # noqa: N802
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(25, 25, 25))

        if self.image is None:
            painter.setPen(QPen(QColor(220, 220, 220)))
            painter.drawText(self.rect(), Qt.AlignCenter, "No image loaded")
            return

        h, w = self.image.shape[:2]
        qimg = QImage(self.image.data, w, h, 3 * w, QImage.Format_RGB888)
        pixmap = QPixmap.fromImage(qimg)
        scale, xoff, yoff = self.image_to_widget_params()
        target = QRectF(xoff, yoff, w * scale, h * scale)
        painter.drawPixmap(target, pixmap, QRectF(0, 0, w, h))

        for i, box in enumerate(self.boxes):
            rect = self.widget_rect_from_box(box)
            color = QColor(0, 255, 255) if i != self.selected_index else QColor(255, 80, 80)
            pen = QPen(color, 2 if i != self.selected_index else 4)
            painter.setPen(pen)
            painter.setBrush(Qt.NoBrush)
            painter.drawRect(rect)
            painter.setPen(QPen(QColor(255, 255, 255)))
            painter.setBrush(QBrush(QColor(0, 0, 0, 160)))
            text = box_label_text(box, include_confidence=False)
            label_rect = QRectF(rect.left(), max(0, rect.top() - 22), max(80, rect.width()), 20)
            painter.drawRect(label_rect)
            painter.drawText(label_rect.adjusted(4, 0, -4, 0), Qt.AlignVCenter | Qt.AlignLeft, text)

    def select_box_at(self, img_pt: QPointF) -> Optional[int]:
        for i in reversed(range(len(self.boxes))):
            if self.boxes[i].rect().contains(img_pt):
                return i
        return None

    def near_bottom_right(self, box: BoxData, img_pt: QPointF) -> bool:
        return abs(img_pt.x() - (box.x + box.w)) < 12 and abs(img_pt.y() - (box.y + box.h)) < 12

    def mousePressEvent(self, event: QMouseEvent):  # noqa: N802
        if self.image is None or event.button() != Qt.LeftButton:
            return
        img_pt = self.image_point_from_widget(event.position())
        h, w = self.image.shape[:2]
        if img_pt.x() < 0 or img_pt.y() < 0 or img_pt.x() > w or img_pt.y() > h:
            return

        if self.add_mode:
            self.drag_mode = "draw"
            self.draw_start_img = img_pt
            self.boxes.append(BoxData("", "", "unknown", math.nan, img_pt.x(), img_pt.y(), 1, 1, "manual"))
            self.selected_index = len(self.boxes) - 1
            self.update()
            return

        idx = self.select_box_at(img_pt)
        self.selected_index = idx
        if self.on_selection_changed:
            self.on_selection_changed(idx)
        if idx is not None:
            self.drag_start_img = img_pt
            box = self.boxes[idx]
            self.original_box = (box.x, box.y, box.w, box.h)
            self.drag_mode = "resize" if self.near_bottom_right(box, img_pt) else "move"
        self.update()

    def mouseMoveEvent(self, event: QMouseEvent):  # noqa: N802
        if self.image is None or self.drag_mode is None or self.selected_index is None:
            return
        img_pt = self.image_point_from_widget(event.position())
        box = self.boxes[self.selected_index]
        h, w = self.image.shape[:2]

        if self.drag_mode == "draw":
            x1, y1 = self.draw_start_img.x(), self.draw_start_img.y()
            x2, y2 = img_pt.x(), img_pt.y()
            box.x = max(0, min(x1, x2))
            box.y = max(0, min(y1, y2))
            box.w = min(w - box.x, abs(x2 - x1))
            box.h = min(h - box.y, abs(y2 - y1))
        elif self.drag_mode == "move" and self.original_box:
            ox, oy, ow, oh = self.original_box
            dx = img_pt.x() - self.drag_start_img.x()
            dy = img_pt.y() - self.drag_start_img.y()
            box.x = min(max(0, ox + dx), max(0, w - ow))
            box.y = min(max(0, oy + dy), max(0, h - oh))
            box.source = append_edited_suffix(box.source)
        elif self.drag_mode == "resize" and self.original_box:
            ox, oy, ow, oh = self.original_box
            box.w = max(2, min(w - ox, ow + img_pt.x() - self.drag_start_img.x()))
            box.h = max(2, min(h - oy, oh + img_pt.y() - self.drag_start_img.y()))
            box.source = append_edited_suffix(box.source)
        self.update()

    def mouseReleaseEvent(self, event: QMouseEvent):  # noqa: N802
        if self.drag_mode == "draw" and self.selected_index is not None:
            box = self.boxes[self.selected_index]
            if box.w < 2 or box.h < 2:
                self.boxes.pop(self.selected_index)
                self.selected_index = None
            self.add_mode = False
        self.drag_mode = None
        self.original_box = None
        if self.on_boxes_changed:
            self.on_boxes_changed()
        if self.on_selection_changed:
            self.on_selection_changed(self.selected_index)
        self.update()


# =============================================================================
# MAIN WINDOW
# =============================================================================

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Maritime Labeling, Detection, and Tracking GUI")
        self.resize(1550, 900)

        self.output_dir = OUTPUT_DIR
        self.annotated_dir = self.output_dir / "reviewed_annotated"
        self.crop_dir = self.output_dir / "reviewed_crops"
        self.pixel_dir = self.output_dir / "reviewed_pixels"
        self.redraw_dir = self.output_dir / "redrawn_from_csv"
        for p in [self.output_dir, self.annotated_dir, self.crop_dir, self.pixel_dir]:
            p.mkdir(parents=True, exist_ok=True)

        if not INPUT_DIR.exists():
            QMessageBox.warning(self, "Input folder missing", f"Input folder not found:\n{INPUT_DIR}\n\nUse File > Open Image Folder.")
            self.image_files: List[Path] = []
        else:
            self.image_files = find_images_recursive(INPUT_DIR)
        if MAX_IMAGES_TO_LOAD is not None:
            self.image_files = self.image_files[: int(MAX_IMAGES_TO_LOAD)]

        self.frames: List[FrameData] = [FrameData(p) for p in self.image_files]
        self.current_index = max(0, min(START_FRAME_INDEX - 1, len(self.frames) - 1)) if self.frames else 0
        self.current_image: Optional[np.ndarray] = None
        self.known_contact_ids: List[str] = []
        self.box_color_mode = BOX_COLOR_MODE
        self.model = None
        self.detector_description = "None"
        self.load_model()
        self.build_ui()
        if self.frames:
            self.load_frame(self.current_index)

    def load_model(self) -> None:
        mode = DETECTOR_MODE.lower()
        if mode == "none":
            self.model = None
            self.detector_description = "None"
            return
        if YOLO is None:
            self.model = None
            self.detector_description = "Ultralytics not installed"
            return
        try:
            if mode == "custom":
                self.model = YOLO(str(CUSTOM_MODEL_PATH))
                self.detector_description = f"Custom: {CUSTOM_MODEL_PATH}"
            else:
                self.model = YOLO(PRETRAINED_MODEL_NAME)
                self.detector_description = f"Pretrained: {PRETRAINED_MODEL_NAME}"
        except Exception as exc:
            self.model = None
            self.detector_description = f"Model load failed: {exc}"

    def build_ui(self) -> None:
        root = QWidget()
        self.setCentralWidget(root)
        layout = QHBoxLayout(root)

        self.canvas = ImageCanvas()
        self.canvas.on_selection_changed = self.on_canvas_selection_changed
        self.canvas.on_boxes_changed = self.refresh_table
        layout.addWidget(self.canvas, stretch=3)

        panel = QWidget()
        grid = QGridLayout(panel)
        layout.addWidget(panel, stretch=1)

        row = 0
        self.model_label = QLabel(f"Detector: {self.detector_description}")
        self.model_label.setWordWrap(True)
        grid.addWidget(self.model_label, row, 0, 1, 2); row += 1

        self.frame_label = QLabel("Frame:")
        grid.addWidget(self.frame_label, row, 0, 1, 2); row += 1
        self.file_label = QLabel("File:")
        self.file_label.setWordWrap(True)
        grid.addWidget(self.file_label, row, 0, 1, 2); row += 1
        self.status_label = QLabel("Status:")
        grid.addWidget(self.status_label, row, 0, 1, 2); row += 1

        self.jump_spin = QSpinBox()
        self.jump_spin.setMinimum(1)
        self.jump_spin.setMaximum(max(1, len(self.frames)))
        self.jump_button = QPushButton("Go To Frame")
        self.jump_button.clicked.connect(self.go_to_frame)
        grid.addWidget(self.jump_spin, row, 0)
        grid.addWidget(self.jump_button, row, 1); row += 1

        prev_btn = QPushButton("Previous")
        next_btn = QPushButton("Next")
        prev_btn.clicked.connect(self.go_previous)
        next_btn.clicked.connect(self.go_next)
        grid.addWidget(prev_btn, row, 0)
        grid.addWidget(next_btn, row, 1); row += 1

        good_btn = QPushButton("Mark Good")
        bad_btn = QPushButton("Mark Bad")
        good_btn.clicked.connect(lambda: self.mark_frame("good"))
        bad_btn.clicked.connect(lambda: self.mark_frame("bad"))
        grid.addWidget(good_btn, row, 0)
        grid.addWidget(bad_btn, row, 1); row += 1

        unreviewed_btn = QPushButton("Mark Unreviewed")
        unreviewed_btn.clicked.connect(lambda: self.mark_frame("unreviewed"))
        grid.addWidget(unreviewed_btn, row, 0, 1, 2); row += 1

        add_btn = QPushButton("Add Box")
        del_btn = QPushButton("Delete Selected")
        add_btn.clicked.connect(self.add_box)
        del_btn.clicked.connect(self.delete_selected_box)
        grid.addWidget(add_btn, row, 0)
        grid.addWidget(del_btn, row, 1); row += 1

        self.label_combo = QComboBox()
        self.label_combo.addItems(MANUAL_LABELS)
        self.label_combo.setCurrentText(DEFAULT_MANUAL_LABEL)
        label_btn = QPushButton("Apply Label")
        label_btn.clicked.connect(self.apply_selected_label)
        grid.addWidget(self.label_combo, row, 0)
        grid.addWidget(label_btn, row, 1); row += 1

        self.contact_field = QLineEdit(DEFAULT_CONTACT_ID)
        self.contact_field.setPlaceholderText("Type ContactID")
        contact_btn = QPushButton("Apply ContactID")
        contact_btn.clicked.connect(self.apply_selected_contact_id)
        grid.addWidget(self.contact_field, row, 0)
        grid.addWidget(contact_btn, row, 1); row += 1

        self.contact_combo = QComboBox()
        self.contact_combo.addItem("<none>")
        use_id_btn = QPushButton("Use Existing ID")
        use_id_btn.clicked.connect(self.use_existing_contact_id)
        grid.addWidget(self.contact_combo, row, 0)
        grid.addWidget(use_id_btn, row, 1); row += 1

        self.color_combo = QComboBox()
        self.color_combo.addItems(["label", "contactID", "source", "single"])
        self.color_combo.setCurrentText(self.box_color_mode)
        self.color_combo.currentTextChanged.connect(self.set_color_mode)
        grid.addWidget(self.color_combo, row, 0)
        grid.addWidget(QLabel("Saved Box Color Mode"), row, 1); row += 1

        rerun_btn = QPushButton("Run/Reload Model")
        clear_btn = QPushButton("Clear Boxes")
        rerun_btn.clicked.connect(self.rerun_detector_current_frame)
        clear_btn.clicked.connect(self.clear_current_boxes)
        grid.addWidget(rerun_btn, row, 0)
        grid.addWidget(clear_btn, row, 1); row += 1

        save_btn = QPushButton("Save Current Frame")
        export_btn = QPushButton("Export All Results")
        save_btn.clicked.connect(self.save_current_frame_only)
        export_btn.clicked.connect(self.export_all_results)
        grid.addWidget(save_btn, row, 0)
        grid.addWidget(export_btn, row, 1); row += 1

        self.help_box = QTextEdit()
        self.help_box.setReadOnly(True)
        self.help_box.setMaximumHeight(130)
        self.help_box.setText(
            "Instructions:\n"
            "1. Model boxes load automatically unless detector mode is none.\n"
            "2. Click a box or table row to select it.\n"
            "3. Drag a box to move it; drag near lower-right to resize.\n"
            "4. Use Add Box to draw missing objects.\n"
            "5. Edit ObjectID, ContactID, and Label in the table.\n"
            "6. Use ContactID to track the same object across frames.\n"
            "7. Choose saved box color mode before export."
        )
        grid.addWidget(self.help_box, row, 0, 1, 2); row += 1

        self.table = QTableWidget(0, 9)
        self.table.setHorizontalHeaderLabels(["ObjectID", "ContactID", "Label", "Confidence", "X", "Y", "W", "H", "Source"])
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        self.table.itemChanged.connect(self.on_table_item_changed)
        self.table.itemSelectionChanged.connect(self.on_table_selection_changed)
        grid.addWidget(self.table, row, 0, 1, 2); row += 1

        self.progress_label = QLabel("Progress:")
        grid.addWidget(self.progress_label, row, 0, 1, 2); row += 1

        save_next_btn = QPushButton("Save && Next")
        save_next_btn.clicked.connect(self.save_and_next)
        grid.addWidget(save_next_btn, row, 0, 1, 2); row += 1

        summary_btn = QPushButton("Show ContactID Summary")
        summary_btn.clicked.connect(self.show_contact_id_summary)
        grid.addWidget(summary_btn, row, 0, 1, 2)

        menubar = self.menuBar()
        file_menu = menubar.addMenu("File")
        open_action = QAction("Open Image Folder", self)
        open_action.triggered.connect(self.open_image_folder)
        file_menu.addAction(open_action)

    # ---------------------------------------------------------------------
    # Navigation and detection
    # ---------------------------------------------------------------------

    def open_image_folder(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "Open Image Folder", str(INPUT_DIR))
        if not path:
            return
        self.image_files = find_images_recursive(Path(path))
        if MAX_IMAGES_TO_LOAD is not None:
            self.image_files = self.image_files[: int(MAX_IMAGES_TO_LOAD)]
        self.frames = [FrameData(p) for p in self.image_files]
        self.current_index = 0
        self.jump_spin.setMaximum(max(1, len(self.frames)))
        if self.frames:
            self.load_frame(0)

    def current_frame(self) -> Optional[FrameData]:
        if not self.frames:
            return None
        return self.frames[self.current_index]

    def load_frame(self, idx: int) -> None:
        if not self.frames:
            return
        self.current_index = max(0, min(idx, len(self.frames) - 1))
        frame = self.current_frame()
        assert frame is not None
        self.current_image = cv2_imread_rgb(frame.image_path)
        if not frame.detected:
            self.run_detector_for_frame(frame)
        self.canvas.set_image_and_boxes(self.current_image, frame.boxes)
        self.update_labels()
        self.refresh_table()

    def run_detector_for_frame(self, frame: FrameData) -> None:
        frame.detected = True
        if self.model is None:
            frame.boxes = []
            return
        try:
            results = self.model(str(frame.image_path), conf=CONFIDENCE_THRESHOLD, verbose=False)
        except Exception as exc:
            QMessageBox.warning(self, "Detection failed", str(exc))
            frame.boxes = []
            return
        boxes: List[BoxData] = []
        if not results:
            frame.boxes = boxes
            return
        result = results[0]
        names = getattr(result, "names", {}) or getattr(self.model, "names", {})
        for i, b in enumerate(result.boxes):
            xyxy = b.xyxy[0].cpu().numpy().astype(float)
            conf = float(b.conf[0].cpu().numpy()) if b.conf is not None else math.nan
            cls_id = int(b.cls[0].cpu().numpy()) if b.cls is not None else -1
            label = str(names.get(cls_id, cls_id))
            if not KEEP_ALL_DETECTED_CLASSES and label not in TARGET_CLASSES:
                continue
            x1, y1, x2, y2 = xyxy
            boxes.append(BoxData(str(len(boxes) + 1), "", label, conf, x1, y1, max(2, x2 - x1), max(2, y2 - y1), DETECTOR_MODE))
        frame.boxes = boxes

    def rerun_detector_current_frame(self) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        if self.model is None:
            QMessageBox.information(self, "No model", "Detector mode is none or model failed to load.")
            return
        if QMessageBox.question(self, "Run model", "Run model again and replace current boxes?") != QMessageBox.Yes:
            return
        frame.detected = False
        self.run_detector_for_frame(frame)
        self.load_frame(self.current_index)

    # ---------------------------------------------------------------------
    # UI updates
    # ---------------------------------------------------------------------

    def update_labels(self) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        self.frame_label.setText(f"Frame: {self.current_index + 1} / {len(self.frames)}")
        self.file_label.setText(f"File: {frame.image_path.name}")
        self.status_label.setText(f"Status: {frame.frame_status} | Boxes: {len(frame.boxes)}")
        self.jump_spin.setValue(self.current_index + 1)
        reviewed = sum(1 for f in self.frames if f.reviewed)
        self.progress_label.setText(
            f"Reviewed: {reviewed} / {len(self.frames)} | ContactIDs: {len(self.known_contact_ids)} | Saved color: {self.box_color_mode}"
        )

    def refresh_table(self) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        self.table.blockSignals(True)
        self.table.setRowCount(len(frame.boxes))
        for r, box in enumerate(frame.boxes):
            values = [
                box.object_id,
                box.contact_id,
                box.label,
                "" if math.isnan(float(box.confidence)) else f"{float(box.confidence):.3f}",
                str(round(box.x)),
                str(round(box.y)),
                str(round(box.w)),
                str(round(box.h)),
                box.source,
            ]
            for c, value in enumerate(values):
                item = QTableWidgetItem(value)
                if c >= 3:
                    item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.table.setItem(r, c, item)
        self.table.blockSignals(False)
        self.update_labels()
        self.canvas.update()

    def on_canvas_selection_changed(self, idx: Optional[int]) -> None:
        frame = self.current_frame()
        if frame is None or idx is None or idx < 0 or idx >= len(frame.boxes):
            return
        box = frame.boxes[idx]
        self.table.blockSignals(True)
        self.table.selectRow(idx)
        self.table.blockSignals(False)
        self.contact_field.setText(box.contact_id)
        if box.label in MANUAL_LABELS:
            self.label_combo.setCurrentText(box.label)

    def on_table_selection_changed(self) -> None:
        items = self.table.selectedItems()
        if not items:
            return
        row = items[0].row()
        self.canvas.selected_index = row
        self.on_canvas_selection_changed(row)
        self.canvas.update()

    def on_table_item_changed(self, item: QTableWidgetItem) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        r, c = item.row(), item.column()
        if r < 0 or r >= len(frame.boxes):
            return
        box = frame.boxes[r]
        value = item.text().strip()
        if c == 0:
            box.object_id = value
        elif c == 1:
            box.contact_id = value
            self.contact_field.setText(value)
            self.register_contact_id(value)
        elif c == 2:
            box.label = value
            if value in MANUAL_LABELS:
                self.label_combo.setCurrentText(value)
        else:
            return
        box.source = append_edited_suffix(box.source)
        self.refresh_table()

    # ---------------------------------------------------------------------
    # Box operations
    # ---------------------------------------------------------------------

    def add_box(self) -> None:
        self.canvas.add_mode = True
        QMessageBox.information(self, "Add Box", "Draw a new box on the image.")

    def delete_selected_box(self) -> None:
        frame = self.current_frame()
        idx = self.canvas.selected_index
        if frame is None or idx is None or idx < 0 or idx >= len(frame.boxes):
            QMessageBox.information(self, "No box selected", "Select a bounding box first.")
            return
        frame.boxes.pop(idx)
        self.canvas.selected_index = None
        self.canvas.update()
        self.refresh_table()

    def apply_selected_label(self) -> None:
        frame = self.current_frame()
        idx = self.canvas.selected_index
        if frame is None or idx is None or idx >= len(frame.boxes):
            QMessageBox.information(self, "No box selected", "Select a bounding box first.")
            return
        frame.boxes[idx].label = self.label_combo.currentText()
        frame.boxes[idx].source = append_edited_suffix(frame.boxes[idx].source)
        self.refresh_table()

    def apply_selected_contact_id(self) -> None:
        frame = self.current_frame()
        idx = self.canvas.selected_index
        if frame is None or idx is None or idx >= len(frame.boxes):
            QMessageBox.information(self, "No box selected", "Select a bounding box first.")
            return
        contact_id = self.contact_field.text().strip()
        frame.boxes[idx].contact_id = contact_id
        frame.boxes[idx].source = append_edited_suffix(frame.boxes[idx].source)
        self.register_contact_id(contact_id)
        self.refresh_table()

    def use_existing_contact_id(self) -> None:
        value = self.contact_combo.currentText()
        if not value or value == "<none>":
            QMessageBox.information(self, "No ContactID", "Select an existing ContactID first.")
            return
        self.contact_field.setText(value)
        self.apply_selected_contact_id()

    def clear_current_boxes(self) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        if QMessageBox.question(self, "Clear Boxes", "Remove all boxes from this frame?") != QMessageBox.Yes:
            return
        frame.boxes = []
        self.canvas.boxes = frame.boxes
        self.canvas.selected_index = None
        self.refresh_table()

    def on_boxes_drawn_or_moved(self) -> None:
        self.refresh_table()

    # ---------------------------------------------------------------------
    # ContactID and frame status
    # ---------------------------------------------------------------------

    def register_contact_id(self, contact_id: str) -> None:
        contact_id = str(contact_id).strip()
        if not contact_id or contact_id == "<none>":
            return
        if contact_id not in self.known_contact_ids:
            self.known_contact_ids.append(contact_id)
            self.contact_combo.clear()
            self.contact_combo.addItem("<none>")
            self.contact_combo.addItems(self.known_contact_ids)

    def show_contact_id_summary(self) -> None:
        lines = ["Known ContactIDs:", ""]
        if not self.known_contact_ids:
            lines.append("None")
        for cid in self.known_contact_ids:
            frames: List[int] = []
            labels: List[str] = []
            box_count = 0
            for fi, frame in enumerate(self.frames, start=1):
                frame_has_contact = False
                for box in frame.boxes:
                    if box.contact_id == cid:
                        box_count += 1
                        frame_has_contact = True
                        if box.label:
                            labels.append(box.label)
                if frame_has_contact:
                    frames.append(fi)
            lines.append(str(cid))
            lines.append(f"  Boxes: {box_count}")
            lines.append(f"  Frames: {compact_frame_list(frames)}")
            lines.append(f"  First frame: {min(frames) if frames else 'none'}")
            lines.append(f"  Last frame: {max(frames) if frames else 'none'}")
            lines.append(f"  Labels: {', '.join(sorted(set(labels))) if labels else 'none'}")
            lines.append("")
        QMessageBox.information(self, "ContactID Summary", "\n".join(lines))

    def mark_frame(self, status: str) -> None:
        frame = self.current_frame()
        if frame is None:
            return
        frame.frame_status = status
        frame.reviewed = status != "unreviewed"
        self.update_labels()

    def set_color_mode(self, mode: str) -> None:
        self.box_color_mode = mode
        self.update_labels()

    # ---------------------------------------------------------------------
    # Navigation
    # ---------------------------------------------------------------------

    def go_previous(self) -> None:
        if self.current_index > 0:
            self.load_frame(self.current_index - 1)

    def go_next(self) -> None:
        if self.current_index < len(self.frames) - 1:
            self.load_frame(self.current_index + 1)

    def go_to_frame(self) -> None:
        self.load_frame(self.jump_spin.value() - 1)

    def save_current_frame_only(self) -> None:
        if self.current_frame() is None:
            return
        self.current_frame().reviewed = True
        self.export_one_frame(self.current_index)
        self.update_labels()
        QMessageBox.information(self, "Saved", "Current frame exported.")

    def save_and_next(self) -> None:
        if self.current_frame() is None:
            return
        self.current_frame().reviewed = True
        self.export_one_frame(self.current_index)
        if self.current_index < len(self.frames) - 1:
            self.load_frame(self.current_index + 1)
        else:
            self.update_labels()
            QMessageBox.information(self, "Done", "Last frame reached.")

    # ---------------------------------------------------------------------
    # Export
    # ---------------------------------------------------------------------

    def export_all_results(self) -> None:
        rows = []
        for idx in range(len(self.frames)):
            rows.extend(self.export_one_frame(idx, show_messages=False))
        all_df = pd.DataFrame(rows)
        csv_path = self.output_dir / "reviewed_detections_all.csv"
        all_df.to_csv(csv_path, index=False)
        QMessageBox.information(self, "Export Complete", f"Export complete.\n\nCSV:\n{csv_path}")

    def export_one_frame(self, idx: int, show_messages: bool = False) -> List[dict]:
        frame = self.frames[idx]
        image = cv2_imread_rgb(frame.image_path)
        img_h, img_w = image.shape[:2]
        annotated = image.copy()
        base_name = frame.image_path.stem
        unique_base = f"{idx + 1:06d}_{base_name}"
        annotated_file = self.annotated_dir / f"{unique_base}_reviewed.png"
        rows: List[dict] = []

        for j, box in enumerate(frame.boxes, start=1):
            x1, y1, x2, y2 = box.to_xyxy(img_w, img_h)
            w, h = x2 - x1 + 1, y2 - y1 + 1
            if w <= 1 or h <= 1:
                continue
            color_rgb = get_box_color(box, self.box_color_mode)
            color_bgr = (color_rgb[2], color_rgb[1], color_rgb[0])
            label_text = box_label_text(box, include_confidence=True)
            cv2.rectangle(annotated, (x1, y1), (x2, y2), color_bgr, 2)
            cv2.putText(annotated, label_text, (x1, max(18, y1 - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color_bgr, 2)

            crop = image[y1 - 1:y2, x1 - 1:x2, :]
            crop_file = self.crop_dir / f"{unique_base}_object_{j}_{safe_name(box.label)}.png"
            pixel_file = self.pixel_dir / f"{unique_base}_object_{j}_pixels.npz"
            cv2_imwrite_rgb(crop_file, crop)
            yy, xx = np.mgrid[y1:y2 + 1, x1:x2 + 1]
            np.savez_compressed(pixel_file, pixel_coords=np.column_stack([xx.ravel(), yy.ravel()]), x1=x1, y1=y1, x2=x2, y2=y2, width=w, height=h, crop=crop)
            area = w * h
            cx, cy = x1 + w / 2.0, y1 + h / 2.0
            rows.append({
                "Frame": base_name,
                "FullPath": str(frame.image_path),
                "FrameIndex": idx + 1,
                "ObjectID": box.object_id,
                "ContactID": box.contact_id,
                "Label": box.label,
                "Confidence": np.nan if box.confidence is None or math.isnan(float(box.confidence)) else float(box.confidence),
                "Source": box.source,
                "FrameStatus": frame.frame_status,
                "Reviewed": bool(frame.reviewed),
                "X1": x1,
                "Y1": y1,
                "X2": x2,
                "Y2": y2,
                "Width": w,
                "Height": h,
                "AreaPixels": area,
                "SizeCategory": classify_object_size(w, h),
                "CenterX": cx,
                "CenterY": cy,
                "NormCenterX": cx / img_w,
                "NormCenterY": cy / img_h,
                "NormWidth": w / img_w,
                "NormHeight": h / img_h,
                "CropFile": str(crop_file),
                "PixelFile": str(pixel_file),
                "ImageWidth": img_w,
                "ImageHeight": img_h,
                "AnnotatedImage": str(annotated_file),
                "DetectorDescription": self.detector_description,
                "BoxColorMode": self.box_color_mode,
                "BoxColorR": color_rgb[0],
                "BoxColorG": color_rgb[1],
                "BoxColorB": color_rgb[2],
            })

        cv2_imwrite_rgb(annotated_file, annotated)

        if not rows and EXPORT_EMPTY_FRAME_ROWS:
            rows.append({
                "Frame": base_name,
                "FullPath": str(frame.image_path),
                "FrameIndex": idx + 1,
                "ObjectID": "",
                "ContactID": "",
                "Label": "none",
                "Confidence": np.nan,
                "Source": "none",
                "FrameStatus": frame.frame_status,
                "Reviewed": bool(frame.reviewed),
                "X1": np.nan,
                "Y1": np.nan,
                "X2": np.nan,
                "Y2": np.nan,
                "Width": np.nan,
                "Height": np.nan,
                "AreaPixels": np.nan,
                "SizeCategory": "none",
                "CenterX": np.nan,
                "CenterY": np.nan,
                "NormCenterX": np.nan,
                "NormCenterY": np.nan,
                "NormWidth": np.nan,
                "NormHeight": np.nan,
                "CropFile": "",
                "PixelFile": "",
                "ImageWidth": img_w,
                "ImageHeight": img_h,
                "AnnotatedImage": str(annotated_file),
                "DetectorDescription": self.detector_description,
                "BoxColorMode": self.box_color_mode,
                "BoxColorR": np.nan,
                "BoxColorG": np.nan,
                "BoxColorB": np.nan,
            })

        per_frame_csv = self.output_dir / f"{unique_base}_reviewed.csv"
        pd.DataFrame(rows).to_csv(per_frame_csv, index=False)
        return rows


def main() -> int:
    app = QApplication(sys.argv)
    win = MainWindow()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
