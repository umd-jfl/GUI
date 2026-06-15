"""
maritime_yolo_review_gui_user_model.py

Python Maritime Review GUI with user-defined detector mode.

Detector modes:
    none       : no automatic model; user manually adds boxes.
    pretrained : use Ultralytics pretrained model, for example yolov8n.pt.
    custom     : use a user-trained Ultralytics model, for example models/best.pt.

Install:
    python -m pip install ultralytics PySide6 opencv-python pandas numpy torch torchvision

Run:
    python maritime_yolo_review_gui_user_model.py
"""
from __future__ import annotations

import math
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np
import pandas as pd
from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QBrush, QColor, QImage, QMouseEvent, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (
    QApplication, QComboBox, QFileDialog, QGroupBox, QHBoxLayout, QLabel,
    QMainWindow, QMessageBox, QPushButton, QTableWidget, QTableWidgetItem,
    QTextEdit, QVBoxLayout, QWidget
)

try:
    from ultralytics import YOLO
except Exception as exc:
    YOLO = None
    YOLO_IMPORT_ERROR = exc
else:
    YOLO_IMPORT_ERROR = None

# ========================= USER SETTINGS =========================
INPUT_DIR = Path("lars_v1.0.0_images") / "val" / "images"
OUTPUT_DIR = Path("LaRS_DetectionOutput_Python_UserModel")

# Options: "none", "pretrained", "custom"
DETECTOR_MODE = "pretrained"
PRETRAINED_MODEL_NAME = "yolov8n.pt"
CUSTOM_MODEL_PATH = Path("models") / "best.pt"

CONFIDENCE_THRESHOLD = 0.25
KEEP_ALL_DETECTED_CLASSES = False
TARGET_CLASSES = ["boat", "airplane", "bird"]

MANUAL_LABELS = [
    "boat", "ship", "submarine", "cargo_ship", "warship", "aircraft_carrier",
    "sailboat", "fishing_boat", "passenger_ship", "airplane", "helicopter",
    "bird", "buoy", "unknown"
]
DEFAULT_MANUAL_LABEL = "ship"
MAX_IMAGES_TO_LOAD = 200  # set to None for all images

@dataclass
class BoxData:
    label: str
    confidence: float
    x: float
    y: float
    w: float
    h: float
    source: str = "model"
    object_id: int = 0

    def as_xyxy_int(self, image_w: int, image_h: int) -> Tuple[int, int, int, int]:
        x1 = max(1, int(round(self.x)))
        y1 = max(1, int(round(self.y)))
        x2 = min(image_w, int(round(self.x + self.w - 1)))
        y2 = min(image_h, int(round(self.y + self.h - 1)))
        return x1, y1, x2, y2

@dataclass
class FrameData:
    image_path: Path
    detected: bool = False
    reviewed: bool = False
    frame_status: str = "unreviewed"
    boxes: List[BoxData] = field(default_factory=list)

class ImageCanvas(QWidget):
    selectionChanged = Signal(int)
    boxesChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumSize(900, 650)
        self.setMouseTracking(True)
        self.image_rgb: Optional[np.ndarray] = None
        self.pixmap: Optional[QPixmap] = None
        self.boxes: List[BoxData] = []
        self.selected_index: Optional[int] = None
        self.add_mode = False
        self.new_box_label = DEFAULT_MANUAL_LABEL
        self.dragging = False
        self.drag_mode = None
        self.drag_start_img = QPointF()
        self.original_box: Optional[BoxData] = None
        self.new_box_start_img = QPointF()
        self.handle_size = 8

    def set_image_and_boxes(self, image_rgb: np.ndarray, boxes: List[BoxData]):
        self.image_rgb = image_rgb
        self.boxes = boxes
        self.selected_index = None
        h, w, ch = image_rgb.shape
        qimg = QImage(image_rgb.data, w, h, ch * w, QImage.Format_RGB888).copy()
        self.pixmap = QPixmap.fromImage(qimg)
        self.update()

    def set_selected_index(self, index: Optional[int]):
        self.selected_index = index
        self.update()

    def set_add_mode(self, enabled: bool, label: str):
        self.add_mode = enabled
        self.new_box_label = label
        self.setCursor(Qt.CrossCursor if enabled else Qt.ArrowCursor)

    def image_rect_on_widget(self) -> QRectF:
        if self.pixmap is None:
            return QRectF()
        scale = min(self.width() / self.pixmap.width(), self.height() / self.pixmap.height())
        draw_w = self.pixmap.width() * scale
        draw_h = self.pixmap.height() * scale
        return QRectF((self.width() - draw_w) / 2, (self.height() - draw_h) / 2, draw_w, draw_h)

    def widget_to_image(self, pos) -> QPointF:
        rect = self.image_rect_on_widget()
        if self.pixmap is None or rect.width() <= 0 or rect.height() <= 0:
            return QPointF()
        return QPointF(
            (pos.x() - rect.x()) / rect.width() * self.pixmap.width(),
            (pos.y() - rect.y()) / rect.height() * self.pixmap.height(),
        )

    def image_to_widget_rect(self, box: BoxData) -> QRectF:
        rect = self.image_rect_on_widget()
        if self.pixmap is None:
            return QRectF()
        return QRectF(
            rect.x() + box.x / self.pixmap.width() * rect.width(),
            rect.y() + box.y / self.pixmap.height() * rect.height(),
            box.w / self.pixmap.width() * rect.width(),
            box.h / self.pixmap.height() * rect.height(),
        )

    def _handle_rects(self, rect: QRectF) -> List[QRectF]:
        s = self.handle_size
        return [
            QRectF(rect.left() - s / 2, rect.top() - s / 2, s, s),
            QRectF(rect.right() - s / 2, rect.top() - s / 2, s, s),
            QRectF(rect.left() - s / 2, rect.bottom() - s / 2, s, s),
            QRectF(rect.right() - s / 2, rect.bottom() - s / 2, s, s),
        ]

    def _hit_test(self, pos) -> Tuple[Optional[int], Optional[str]]:
        for i in reversed(range(len(self.boxes))):
            rect = self.image_to_widget_rect(self.boxes[i])
            for handle, mode in zip(self._handle_rects(rect), ["resize_tl", "resize_tr", "resize_bl", "resize_br"]):
                if handle.contains(pos):
                    return i, mode
            if rect.contains(pos):
                return i, "move"
        return None, None

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(240, 240, 240))
        if self.pixmap is None:
            painter.drawText(self.rect(), Qt.AlignCenter, "No image loaded")
            return
        painter.drawPixmap(self.image_rect_on_widget().toRect(), self.pixmap)
        for i, box in enumerate(self.boxes):
            rect = self.image_to_widget_rect(box)
            selected = i == self.selected_index
            color = QColor(0, 150, 255) if selected else QColor(230, 230, 0)
            painter.setPen(QPen(color, 3 if selected else 2))
            painter.setBrush(Qt.NoBrush)
            painter.drawRect(rect)
            label = f"{box.label} manual" if math.isnan(box.confidence) else f"{box.label} {box.confidence:.2f}"
            painter.setPen(QPen(Qt.black, 1))
            painter.setBrush(QBrush(color))
            label_rect = QRectF(rect.x(), max(0, rect.y() - 20), max(90, len(label) * 7), 20)
            painter.drawRect(label_rect)
            painter.drawText(label_rect.adjusted(3, 0, 0, 0), Qt.AlignVCenter, label)
            if selected:
                painter.setBrush(QBrush(QColor(0, 150, 255)))
                for handle in self._handle_rects(rect):
                    painter.drawRect(handle)

    def mousePressEvent(self, event: QMouseEvent):
        if self.pixmap is None or self.image_rgb is None or event.button() != Qt.LeftButton:
            return
        img_pt = self.widget_to_image(event.position())
        image_h, image_w = self.image_rgb.shape[:2]
        if img_pt.x() < 0 or img_pt.y() < 0 or img_pt.x() > image_w or img_pt.y() > image_h:
            return
        if self.add_mode:
            self.dragging = True
            self.drag_mode = "new"
            self.new_box_start_img = img_pt
            self.boxes.append(BoxData(self.new_box_label, float("nan"), img_pt.x(), img_pt.y(), 1, 1, "manual", len(self.boxes) + 1))
            self.selected_index = len(self.boxes) - 1
            self.selectionChanged.emit(self.selected_index)
            self.update()
            return
        idx, mode = self._hit_test(event.position())
        self.selected_index = idx
        if idx is not None:
            self.selectionChanged.emit(idx)
            self.dragging = True
            self.drag_mode = mode
            self.drag_start_img = img_pt
            b = self.boxes[idx]
            self.original_box = BoxData(b.label, b.confidence, b.x, b.y, b.w, b.h, b.source, b.object_id)
        else:
            self.selectionChanged.emit(-1)
        self.update()

    def mouseMoveEvent(self, event: QMouseEvent):
        if not self.dragging or self.selected_index is None or self.pixmap is None or self.image_rgb is None:
            return
        img_pt = self.widget_to_image(event.position())
        img_h, img_w = self.image_rgb.shape[:2]
        img_pt.setX(max(0, min(img_w, img_pt.x())))
        img_pt.setY(max(0, min(img_h, img_pt.y())))
        box = self.boxes[self.selected_index]
        if self.drag_mode == "new":
            x1 = min(self.new_box_start_img.x(), img_pt.x())
            y1 = min(self.new_box_start_img.y(), img_pt.y())
            x2 = max(self.new_box_start_img.x(), img_pt.x())
            y2 = max(self.new_box_start_img.y(), img_pt.y())
            box.x, box.y, box.w, box.h = x1, y1, max(1, x2 - x1), max(1, y2 - y1)
            box.source = "manual"
        elif self.drag_mode == "move" and self.original_box is not None:
            dx = img_pt.x() - self.drag_start_img.x()
            dy = img_pt.y() - self.drag_start_img.y()
            box.x = max(0, min(img_w - box.w, self.original_box.x + dx))
            box.y = max(0, min(img_h - box.h, self.original_box.y + dy))
            if "_edited" not in box.source:
                box.source += "_edited"
        elif self.drag_mode and self.drag_mode.startswith("resize") and self.original_box is not None:
            x1, y1 = self.original_box.x, self.original_box.y
            x2, y2 = self.original_box.x + self.original_box.w, self.original_box.y + self.original_box.h
            if self.drag_mode == "resize_tl": x1, y1 = img_pt.x(), img_pt.y()
            elif self.drag_mode == "resize_tr": x2, y1 = img_pt.x(), img_pt.y()
            elif self.drag_mode == "resize_bl": x1, y2 = img_pt.x(), img_pt.y()
            elif self.drag_mode == "resize_br": x2, y2 = img_pt.x(), img_pt.y()
            nx1, ny1 = max(0, min(x1, x2 - 1)), max(0, min(y1, y2 - 1))
            nx2, ny2 = min(img_w, max(x2, nx1 + 1)), min(img_h, max(y2, ny1 + 1))
            box.x, box.y, box.w, box.h = nx1, ny1, nx2 - nx1, ny2 - ny1
            if "_edited" not in box.source:
                box.source += "_edited"
        self.boxesChanged.emit()
        self.update()

    def mouseReleaseEvent(self, event: QMouseEvent):
        if self.dragging:
            self.dragging = False
            self.drag_mode = None
            self.original_box = None
            self.boxesChanged.emit()
            self.update()

class MaritimeReviewGUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Maritime Review GUI - User Defined Model")
        self.resize(1450, 900)
        self.model = None
        self.model_description = "None"
        self.input_dir = INPUT_DIR
        self.output_dir = OUTPUT_DIR
        self.frame_data: List[FrameData] = []
        self.current_index = 0
        self.current_image_rgb: Optional[np.ndarray] = None
        self._build_ui()
        self._load_model()
        self._load_images()
        if self.frame_data:
            self.load_frame(0)

    def _build_ui(self):
        central = QWidget(); self.setCentralWidget(central)
        main_layout = QHBoxLayout(central)
        image_group = QGroupBox("Image Review")
        image_layout = QVBoxLayout(image_group)
        self.canvas = ImageCanvas()
        self.status_bar_label = QLabel("Ready")
        image_layout.addWidget(self.canvas); image_layout.addWidget(self.status_bar_label)
        control_group = QGroupBox("Controls")
        control_layout = QVBoxLayout(control_group)
        self.model_label = QLabel("Detector:"); self.model_label.setWordWrap(True)
        self.frame_label = QLabel("Frame:"); self.file_label = QLabel("File:"); self.file_label.setWordWrap(True)
        self.status_label = QLabel("Status:")
        self.prev_button = QPushButton("Previous"); self.next_button = QPushButton("Next")
        self.mark_good_button = QPushButton("Mark Good"); self.mark_bad_button = QPushButton("Mark Bad")
        self.add_box_button = QPushButton("Add Box"); self.delete_button = QPushButton("Delete Selected")
        self.label_dropdown = QComboBox(); self.label_dropdown.addItems(MANUAL_LABELS); self.label_dropdown.setCurrentText(DEFAULT_MANUAL_LABEL)
        self.apply_label_button = QPushButton("Apply Label")
        self.rerun_button = QPushButton("Run/Reload Model"); self.clear_button = QPushButton("Clear Boxes")
        self.save_frame_button = QPushButton("Save Current Frame"); self.export_button = QPushButton("Export All Results")
        self.choose_input_button = QPushButton("Choose Input Folder"); self.save_next_button = QPushButton("Save && Next")
        nav = QHBoxLayout(); nav.addWidget(self.prev_button); nav.addWidget(self.next_button)
        review = QHBoxLayout(); review.addWidget(self.mark_good_button); review.addWidget(self.mark_bad_button)
        edit = QHBoxLayout(); edit.addWidget(self.add_box_button); edit.addWidget(self.delete_button)
        label_layout = QHBoxLayout(); label_layout.addWidget(self.label_dropdown); label_layout.addWidget(self.apply_label_button)
        rerun = QHBoxLayout(); rerun.addWidget(self.rerun_button); rerun.addWidget(self.clear_button)
        self.help_text = QTextEdit(); self.help_text.setReadOnly(True); self.help_text.setMaximumHeight(120)
        self.help_text.setText("Instructions:\n1. Model boxes load automatically unless DETECTOR_MODE = none.\n2. Click a box or table row to select it.\n3. Drag/resize boxes on the image.\n4. Use Add Box to draw a missing box.\n5. Use dropdown + Apply Label to relabel.\n6. Mark frame Good or Bad.\n7. Save && Next exports current frame.\n8. Export All Results saves all frames.")
        self.box_table = QTableWidget(0, 8)
        self.box_table.setHorizontalHeaderLabels(["ID", "Label", "Confidence", "X", "Y", "W", "H", "Source"])
        self.box_table.setSelectionBehavior(QTableWidget.SelectRows); self.box_table.setSelectionMode(QTableWidget.SingleSelection)
        self.progress_label = QLabel("Reviewed: 0 / 0")
        for w in [self.model_label, self.frame_label, self.file_label, self.status_label]: control_layout.addWidget(w)
        for l in [nav, review, edit, label_layout, rerun]: control_layout.addLayout(l)
        for w in [self.save_frame_button, self.export_button, self.choose_input_button, self.help_text, self.box_table, self.progress_label, self.save_next_button]: control_layout.addWidget(w)
        main_layout.addWidget(image_group, stretch=3); main_layout.addWidget(control_group, stretch=1)
        self.prev_button.clicked.connect(self.previous_frame); self.next_button.clicked.connect(self.next_frame)
        self.mark_good_button.clicked.connect(lambda: self.mark_frame("good")); self.mark_bad_button.clicked.connect(lambda: self.mark_frame("bad"))
        self.add_box_button.clicked.connect(self.toggle_add_box_mode); self.delete_button.clicked.connect(self.delete_selected_box)
        self.apply_label_button.clicked.connect(self.apply_selected_label); self.rerun_button.clicked.connect(self.rerun_model); self.clear_button.clicked.connect(self.clear_boxes)
        self.save_frame_button.clicked.connect(self.save_current_frame); self.export_button.clicked.connect(self.export_all_results)
        self.save_next_button.clicked.connect(self.save_and_next); self.choose_input_button.clicked.connect(self.choose_input_folder)
        self.box_table.cellClicked.connect(self.table_cell_clicked); self.box_table.cellChanged.connect(self.table_cell_changed)
        self.canvas.selectionChanged.connect(self.canvas_selection_changed); self.canvas.boxesChanged.connect(self.refresh_table)

    def _load_model(self):
        mode = DETECTOR_MODE.lower().strip()
        if mode == "none":
            self.model, self.model_description = None, "None"
            self.model_label.setText("Detector: None")
            return
        if YOLO is None:
            QMessageBox.critical(self, "Ultralytics Import Error", f"Could not import ultralytics YOLO.\n\n{YOLO_IMPORT_ERROR}\n\nInstall with: python -m pip install ultralytics")
            raise RuntimeError("ultralytics is not installed")
        if mode == "pretrained":
            source = PRETRAINED_MODEL_NAME; self.model_description = f"Pretrained: {PRETRAINED_MODEL_NAME}"
        elif mode == "custom":
            if not CUSTOM_MODEL_PATH.exists():
                QMessageBox.critical(self, "Custom Model Not Found", f"Custom model not found:\n{CUSTOM_MODEL_PATH}")
                raise FileNotFoundError(CUSTOM_MODEL_PATH)
            source = str(CUSTOM_MODEL_PATH); self.model_description = f"Custom: {CUSTOM_MODEL_PATH}"
        else:
            raise ValueError("DETECTOR_MODE must be none, pretrained, or custom")
        self.status_bar_label.setText(f"Loading detector: {source}"); QApplication.processEvents()
        self.model = YOLO(source)
        self.model_label.setText(f"Detector: {self.model_description}")

    def _load_images(self):
        if not self.input_dir.exists():
            QMessageBox.warning(self, "Input Folder Not Found", f"Input folder not found:\n{self.input_dir}\n\nUse Choose Input Folder or update INPUT_DIR.")
            return
        paths = find_images_recursive(self.input_dir)
        if MAX_IMAGES_TO_LOAD is not None: paths = paths[:int(MAX_IMAGES_TO_LOAD)]
        self.frame_data = [FrameData(p) for p in paths]
        self.status_bar_label.setText(f"Images loaded: {len(self.frame_data)}")

    def choose_input_folder(self):
        folder = QFileDialog.getExistingDirectory(self, "Choose Image Folder", str(self.input_dir))
        if folder:
            self.input_dir = Path(folder); self._load_images()
            if self.frame_data: self.load_frame(0)

    def load_frame(self, index: int):
        if not self.frame_data: return
        self.current_index = max(0, min(index, len(self.frame_data)-1))
        frame = self.frame_data[self.current_index]
        img_bgr = cv2.imread(str(frame.image_path))
        if img_bgr is None:
            QMessageBox.warning(self, "Image Error", f"Could not read image:\n{frame.image_path}"); return
        self.current_image_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
        if not frame.detected: self.run_detector_for_current_frame()
        self.canvas.set_image_and_boxes(self.current_image_rgb, frame.boxes)
        self.refresh_ui_labels(); self.refresh_table()

    def run_detector_for_current_frame(self):
        frame = self.frame_data[self.current_index]
        if DETECTOR_MODE.lower().strip() == "none" or self.model is None:
            frame.boxes = []; frame.detected = True; return
        results = self.model.predict(source=str(frame.image_path), conf=CONFIDENCE_THRESHOLD, verbose=False)
        boxes = []
        if results:
            r = results[0]; names = r.names
            if r.boxes is not None:
                for b in r.boxes:
                    xyxy = b.xyxy[0].cpu().numpy(); conf = float(b.conf[0].cpu().numpy()); cls_id = int(b.cls[0].cpu().numpy())
                    label = str(names.get(cls_id, cls_id))
                    if (not KEEP_ALL_DETECTED_CLASSES) and label not in TARGET_CLASSES: continue
                    x1, y1, x2, y2 = xyxy
                    boxes.append(BoxData(label, conf, float(x1), float(y1), float(x2-x1), float(y2-y1), DETECTOR_MODE, len(boxes)+1))
        frame.boxes = boxes; frame.detected = True

    def refresh_ui_labels(self):
        f = self.frame_data[self.current_index]
        self.model_label.setText(f"Detector: {self.model_description}")
        self.frame_label.setText(f"Frame: {self.current_index+1} / {len(self.frame_data)}")
        self.file_label.setText(f"File: {f.image_path.name}")
        self.status_label.setText(f"Status: {f.frame_status} | Boxes: {len(f.boxes)}")
        self.progress_label.setText(f"Reviewed: {sum(1 for x in self.frame_data if x.reviewed)} / {len(self.frame_data)}")
        self.status_bar_label.setText(f"Frame {self.current_index+1}/{len(self.frame_data)} | {f.image_path} | Status: {f.frame_status}")

    def refresh_table(self):
        if not self.frame_data: return
        f = self.frame_data[self.current_index]
        self.box_table.blockSignals(True); self.box_table.setRowCount(len(f.boxes))
        for row, box in enumerate(f.boxes):
            vals = [row+1, box.label, "" if math.isnan(box.confidence) else f"{box.confidence:.4f}", round(box.x), round(box.y), round(box.w), round(box.h), box.source]
            for col, val in enumerate(vals): self.box_table.setItem(row, col, QTableWidgetItem(str(val)))
        self.box_table.blockSignals(False); self.refresh_ui_labels()

    def table_cell_clicked(self, row, col): self.canvas.set_selected_index(row)
    def table_cell_changed(self, row, col):
        if not self.frame_data or col != 1: return
        f = self.frame_data[self.current_index]
        if 0 <= row < len(f.boxes):
            item = self.box_table.item(row, col)
            if item and item.text().strip():
                f.boxes[row].label = item.text().strip()
                if "_edited" not in f.boxes[row].source: f.boxes[row].source += "_edited"
                self.canvas.update(); self.refresh_table()
    def canvas_selection_changed(self, index):
        if index < 0: self.box_table.clearSelection()
        else: self.box_table.selectRow(index); self.canvas.set_selected_index(index)
    def previous_frame(self):
        if self.current_index > 0: self.load_frame(self.current_index-1)
    def next_frame(self):
        if self.current_index < len(self.frame_data)-1: self.load_frame(self.current_index+1)
    def mark_frame(self, status):
        f = self.frame_data[self.current_index]; f.frame_status = status; f.reviewed = True; self.refresh_ui_labels()
    def toggle_add_box_mode(self):
        enabled = not self.canvas.add_mode; self.canvas.set_add_mode(enabled, self.label_dropdown.currentText()); self.add_box_button.setText("Cancel Add Box" if enabled else "Add Box")
    def delete_selected_box(self):
        idx = self.canvas.selected_index
        if idx is None: QMessageBox.information(self, "No Box Selected", "Select a box first."); return
        f = self.frame_data[self.current_index]
        if 0 <= idx < len(f.boxes): del f.boxes[idx]
        reassign_object_ids(f.boxes); self.canvas.set_image_and_boxes(self.current_image_rgb, f.boxes); self.refresh_table()
    def apply_selected_label(self):
        idx = self.canvas.selected_index
        if idx is None: QMessageBox.information(self, "No Box Selected", "Select a box first."); return
        f = self.frame_data[self.current_index]
        if 0 <= idx < len(f.boxes):
            f.boxes[idx].label = self.label_dropdown.currentText()
            if "_edited" not in f.boxes[idx].source: f.boxes[idx].source += "_edited"
        self.canvas.update(); self.refresh_table()
    def rerun_model(self):
        if DETECTOR_MODE.lower().strip() == "none" or self.model is None:
            QMessageBox.information(self, "No Model", "DETECTOR_MODE is set to none. No model will run."); return
        if QMessageBox.question(self, "Run Model", "Run model again and replace current boxes?", QMessageBox.Yes|QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
            f = self.frame_data[self.current_index]; f.detected = False; self.run_detector_for_current_frame(); self.canvas.set_image_and_boxes(self.current_image_rgb, f.boxes); self.refresh_table()
    def clear_boxes(self):
        if QMessageBox.question(self, "Clear Boxes", "Remove all boxes from this frame?", QMessageBox.Yes|QMessageBox.No, QMessageBox.No) == QMessageBox.Yes:
            f = self.frame_data[self.current_index]; f.boxes = []; self.canvas.set_image_and_boxes(self.current_image_rgb, f.boxes); self.refresh_table()
    def save_current_frame(self):
        self.frame_data[self.current_index].reviewed = True; self.export_one_frame(self.current_index); self.refresh_ui_labels(); QMessageBox.information(self, "Saved", "Current frame exported.")
    def save_and_next(self):
        self.frame_data[self.current_index].reviewed = True; self.export_one_frame(self.current_index); self.refresh_ui_labels()
        if self.current_index < len(self.frame_data)-1: self.load_frame(self.current_index+1)
        else: QMessageBox.information(self, "Done", "Last frame reached.")
    def export_all_results(self):
        if QMessageBox.question(self, "Export All Results", "Export all boxes to CSV, crops, pixels, and annotated images?", QMessageBox.Yes|QMessageBox.No, QMessageBox.Yes) != QMessageBox.Yes: return
        rows = []
        for idx in range(len(self.frame_data)): rows.extend(self.export_one_frame(idx, True))
        self.output_dir.mkdir(parents=True, exist_ok=True)
        csv = self.output_dir / "reviewed_detections_all.csv"; pd.DataFrame(rows).to_csv(csv, index=False)
        QMessageBox.information(self, "Export Complete", f"Export complete.\n\nCSV:\n{csv}")

    def export_one_frame(self, idx: int, return_rows: bool=False) -> List[Dict[str, Any]]:
        f = self.frame_data[idx]
        img = cv2.imread(str(f.image_path))
        if img is None: return []
        h, w = img.shape[:2]
        annotated_dir = self.output_dir / "reviewed_annotated"; crop_dir = self.output_dir / "reviewed_crops"; pixel_dir = self.output_dir / "reviewed_pixels"
        for d in [annotated_dir, crop_dir, pixel_dir]: d.mkdir(parents=True, exist_ok=True)
        base = f.image_path.stem; unique = f"{idx+1:06d}_{base}"; annotated = img.copy(); rows = []
        for j, box in enumerate(f.boxes, 1):
            x1,y1,x2,y2 = box.as_xyxy_int(w,h); fw, fh = x2-x1+1, y2-y1+1
            if fw <= 1 or fh <= 1: continue
            area = fw*fh; size = classify_object_size(fw, fh); cx, cy = x1+fw/2, y1+fh/2
            crop = img[y1:y2+1, x1:x2+1]; safe = make_safe_filename(box.label)
            crop_file = crop_dir / f"{unique}_object_{j}_{safe}.png"; pixel_file = pixel_dir / f"{unique}_object_{j}_pixels.npz"
            cv2.imwrite(str(crop_file), crop)
            xs, ys = np.meshgrid(np.arange(x1, x2+1), np.arange(y1, y2+1)); pix = np.column_stack([xs.ravel(), ys.ravel()])
            np.savez_compressed(pixel_file, pixelCoords=pix, x1=x1, y1=y1, x2=x2, y2=y2, finalW=fw, finalH=fh, areaPixels=area, centerX=cx, centerY=cy, normCenterX=cx/w, normCenterY=cy/h, normWidth=fw/w, normHeight=fh/h, objectCrop=crop)
            label_text = f"{box.label} manual" if math.isnan(box.confidence) else f"{box.label} {box.confidence:.2f}"
            cv2.rectangle(annotated, (x1,y1), (x2,y2), (0,255,255), 2); cv2.putText(annotated, label_text, (x1, max(20,y1-8)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0,255,255), 2)
            rows.append({"Frame":base,"FullPath":str(f.image_path),"FrameIndex":idx+1,"ObjectID":j,"Label":box.label,"Confidence":None if math.isnan(box.confidence) else box.confidence,"Source":box.source,"FrameStatus":f.frame_status,"Reviewed":f.reviewed,"X1":x1,"Y1":y1,"X2":x2,"Y2":y2,"Width":fw,"Height":fh,"AreaPixels":area,"SizeCategory":size,"CenterX":cx,"CenterY":cy,"NormCenterX":cx/w,"NormCenterY":cy/h,"NormWidth":fw/w,"NormHeight":fh/h,"CropFile":str(crop_file),"PixelFile":str(pixel_file),"ImageWidth":w,"ImageHeight":h,"DetectorDescription":self.model_description})
        cv2.imwrite(str(annotated_dir / f"{unique}_reviewed.png"), annotated)
        if not rows:
            rows.append({"Frame":base,"FullPath":str(f.image_path),"FrameIndex":idx+1,"ObjectID":None,"Label":"none","Confidence":None,"Source":"none","FrameStatus":f.frame_status,"Reviewed":f.reviewed,"X1":None,"Y1":None,"X2":None,"Y2":None,"Width":None,"Height":None,"AreaPixels":None,"SizeCategory":"none","CenterX":None,"CenterY":None,"NormCenterX":None,"NormCenterY":None,"NormWidth":None,"NormHeight":None,"CropFile":"","PixelFile":"","ImageWidth":w,"ImageHeight":h,"DetectorDescription":self.model_description})
        pd.DataFrame(rows).to_csv(self.output_dir / f"{unique}_reviewed.csv", index=False)
        return rows

def find_images_recursive(root_dir: Path) -> List[Path]:
    exts = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
    return sorted([p for p in root_dir.rglob("*") if p.is_file() and p.suffix.lower() in exts])

def reassign_object_ids(boxes: List[BoxData]):
    for i, b in enumerate(boxes, 1): b.object_id = i

def classify_object_size(width_pixels: float, height_pixels: float) -> str:
    area = width_pixels * height_pixels
    if area < 32*32: return "tiny"
    if area < 96*96: return "small"
    if area < 224*224: return "medium"
    return "large"

def make_safe_filename(label: str) -> str:
    safe = str(label)
    for ch in [' ', '/', '\\', ':', '*', '?', '"', '<', '>', '|']: safe = safe.replace(ch, '_')
    return safe

def main():
    app = QApplication(sys.argv)
    window = MaritimeReviewGUI()
    window.show()
    sys.exit(app.exec())

if __name__ == "__main__":
    main()
