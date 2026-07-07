"""
Python Maritime Labeling, Detection, and Tracking GUI v5.
Matches current MATLAB behavior: startup image-folder/video picker, output folder picker,
scrollable controls, editable boxes/ObjectID/ContactID/Label, ContactID summary,
empty-frame export, saved color modes, and CSV/crop/pixel/annotated exports.
"""
from __future__ import annotations
import sys, math, hashlib
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional, Tuple, Dict, Any
import cv2, numpy as np, pandas as pd
from PySide6.QtCore import Qt, QRectF, QPointF, Signal
from PySide6.QtGui import QBrush, QColor, QImage, QMouseEvent, QPainter, QPen, QPixmap
from PySide6.QtWidgets import *
try:
    from ultralytics import YOLO
except Exception as exc:
    YOLO=None; YOLO_IMPORT_ERROR=exc
else:
    YOLO_IMPORT_ERROR=None

DETECTOR_MODE="pretrained"      # "none", "pretrained", or "custom"
PRETRAINED_MODEL_NAME="yolov8n.pt"
CUSTOM_MODEL_PATH=Path("models")/"best.pt"
CONFIDENCE_THRESHOLD=0.25
KEEP_ALL_DETECTED_CLASSES=False
TARGET_CLASSES=["boat","airplane","bird"]
MANUAL_LABELS=["boat","ship","submarine","cargo_ship","warship","aircraft_carrier","sailboat","fishing_boat","passenger_ship","airplane","helicopter","bird","buoy","dock","unknown"]
DEFAULT_MANUAL_LABEL="ship"
START_FRAME_INDEX=1
MAX_IMAGES_TO_LOAD=200   # None for all
EXPORT_EMPTY_FRAME_ROWS=True
DEFAULT_CONTACT_ID=""
VIDEO_FRAME_STEP=5
BOX_COLOR_MODE="label"  # label/contactID/source/single
DEFAULT_BOX_COLOR=(255,255,0)
LABEL_COLOR_MAP={"boat":(0,255,255),"ship":(255,255,0),"submarine":(255,0,255),"cargo_ship":(255,128,0),"warship":(255,0,0),"aircraft_carrier":(128,0,255),"sailboat":(0,255,0),"fishing_boat":(0,128,255),"passenger_ship":(128,255,0),"airplane":(0,0,255),"helicopter":(128,128,255),"bird":(0,255,128),"buoy":(255,128,128),"dock":(128,128,128),"unknown":(255,255,255)}
SOURCE_COLOR_MAP={"pretrained":(255,255,0),"custom":(0,255,0),"manual":(0,255,255),"pretrained_edited":(255,128,0),"custom_edited":(128,255,0),"manual_edited":(0,128,255),"none":(255,255,255)}

@dataclass
class BoxData:
    object_id:str; contact_id:str; label:str; confidence:float; x:float; y:float; w:float; h:float; source:str="model"
    def as_xyxy_int(self, image_w:int, image_h:int)->Tuple[int,int,int,int]:
        x1=max(1,int(round(self.x))); y1=max(1,int(round(self.y)))
        x2=min(image_w,int(round(self.x+self.w-1))); y2=min(image_h,int(round(self.y+self.h-1)))
        return x1,y1,x2,y2
    def has_valid_position(self)->bool: return self.w>1 and self.h>1
@dataclass
class FrameData:
    image_path:Path; detected:bool=False; reviewed:bool=False; frame_status:str="unreviewed"; boxes:List[BoxData]=field(default_factory=list)

class StartupDialog(QDialog):
    def __init__(self):
        super().__init__(); self.setWindowTitle("Select Input and Output"); self.resize(580,260)
        self.input_type="images"; self.input_path=""; self.output_path=""; self.video_frame_step=VIDEO_FRAME_STEP
        l=QVBoxLayout(self); g=QGroupBox("Input Type"); gl=QHBoxLayout(g)
        self.image_radio=QRadioButton("Image Folder"); self.video_radio=QRadioButton("Video File"); self.image_radio.setChecked(True)
        gl.addWidget(self.image_radio); gl.addWidget(self.video_radio); l.addWidget(g)
        hl=QHBoxLayout(); self.input_field=QLineEdit(); self.input_btn=QPushButton("Browse Input"); hl.addWidget(self.input_field); hl.addWidget(self.input_btn); l.addLayout(hl)
        ol=QHBoxLayout(); self.output_field=QLineEdit(); self.output_btn=QPushButton("Browse Output"); ol.addWidget(self.output_field); ol.addWidget(self.output_btn); l.addLayout(ol)
        sl=QHBoxLayout(); sl.addWidget(QLabel("Video frame step:")); self.step_spin=QSpinBox(); self.step_spin.setRange(1,10000); self.step_spin.setValue(VIDEO_FRAME_STEP); sl.addWidget(self.step_spin); sl.addStretch(); l.addLayout(sl)
        bb=QDialogButtonBox(QDialogButtonBox.Ok|QDialogButtonBox.Cancel); l.addWidget(bb)
        self.input_btn.clicked.connect(self.browse_input); self.output_btn.clicked.connect(self.browse_output); bb.accepted.connect(self.validate_and_accept); bb.rejected.connect(self.reject)
    def browse_input(self):
        if self.image_radio.isChecked():
            p=QFileDialog.getExistingDirectory(self,"Select image folder to review",str(Path.cwd()))
        else:
            p,_=QFileDialog.getOpenFileName(self,"Select video file to review",str(Path.cwd()),"Video Files (*.mp4 *.avi *.mov *.mkv *.wmv *.mpg *.mpeg);;All Files (*)")
        if p: self.input_field.setText(p)
    def browse_output(self):
        p=QFileDialog.getExistingDirectory(self,"Select output folder for reviewed results",str(Path.cwd()))
        if p: self.output_field.setText(p)
    def validate_and_accept(self):
        ip=self.input_field.text().strip(); op=self.output_field.text().strip()
        if not ip or not op: QMessageBox.warning(self,"Missing Selection","Select both input and output."); return
        if self.image_radio.isChecked() and not Path(ip).is_dir(): QMessageBox.warning(self,"Invalid Input","Image folder does not exist."); return
        if self.video_radio.isChecked() and not Path(ip).is_file(): QMessageBox.warning(self,"Invalid Input","Video file does not exist."); return
        self.input_type="images" if self.image_radio.isChecked() else "video"; self.input_path=ip; self.output_path=op; self.video_frame_step=int(self.step_spin.value()); self.accept()

class ImageCanvas(QWidget):
    selectionChanged=Signal(int); boxesChanged=Signal()
    def __init__(self):
        super().__init__(); self.setMinimumSize(900,650); self.setMouseTracking(True); self.image_rgb=None; self.pixmap=None; self.boxes=[]; self.selected_index=None; self.add_mode=False; self.new_box_label=DEFAULT_MANUAL_LABEL; self.new_box_contact_id=""; self.dragging=False; self.drag_mode=None; self.drag_start_img=QPointF(); self.original_box=None; self.new_box_start_img=QPointF(); self.handle_size=8
    def set_image_and_boxes(self,img,boxes):
        self.image_rgb=img; self.boxes=boxes; self.selected_index=None; h,w,ch=img.shape; self.pixmap=QPixmap.fromImage(QImage(img.data,w,h,ch*w,QImage.Format_RGB888).copy()); self.update()
    def set_selected_index(self,i): self.selected_index=i; self.update()
    def set_add_mode(self,en,label,cid): self.add_mode=en; self.new_box_label=label; self.new_box_contact_id=cid; self.setCursor(Qt.CrossCursor if en else Qt.ArrowCursor)
    def image_rect_on_widget(self):
        if self.pixmap is None: return QRectF()
        s=min(self.width()/self.pixmap.width(), self.height()/self.pixmap.height()); dw=self.pixmap.width()*s; dh=self.pixmap.height()*s
        return QRectF((self.width()-dw)/2,(self.height()-dh)/2,dw,dh)
    def widget_to_image(self,pos):
        r=self.image_rect_on_widget();
        if self.pixmap is None or r.width()<=0: return QPointF()
        return QPointF((pos.x()-r.x())/r.width()*self.pixmap.width(), (pos.y()-r.y())/r.height()*self.pixmap.height())
    def image_to_widget_rect(self,b):
        r=self.image_rect_on_widget();
        if self.pixmap is None: return QRectF()
        return QRectF(r.x()+b.x/self.pixmap.width()*r.width(), r.y()+b.y/self.pixmap.height()*r.height(), b.w/self.pixmap.width()*r.width(), b.h/self.pixmap.height()*r.height())
    def _handle_rects(self,r):
        hs=self.handle_size; return [QRectF(r.left()-hs/2,r.top()-hs/2,hs,hs),QRectF(r.right()-hs/2,r.top()-hs/2,hs,hs),QRectF(r.left()-hs/2,r.bottom()-hs/2,hs,hs),QRectF(r.right()-hs/2,r.bottom()-hs/2,hs,hs)]
    def paintEvent(self,e):
        p=QPainter(self); p.fillRect(self.rect(),QColor(240,240,240))
        if self.pixmap is None: p.drawText(self.rect(),Qt.AlignCenter,"No image loaded"); return
        p.drawPixmap(self.image_rect_on_widget().toRect(),self.pixmap)
        for i,b in enumerate(self.boxes):
            r=self.image_to_widget_rect(b); sel=i==self.selected_index; col=QColor(0,150,255) if sel else QColor(230,230,0); p.setPen(QPen(col,3 if sel else 2)); p.setBrush(Qt.NoBrush); p.drawRect(r)
            txt=make_roi_label(b); p.setPen(QPen(Qt.black,1)); p.setBrush(QBrush(col)); lr=QRectF(r.x(),max(0,r.y()-20),max(90,len(txt)*7),20); p.drawRect(lr); p.drawText(lr.adjusted(3,0,0,0),Qt.AlignVCenter,txt)
            if sel:
                p.setBrush(QBrush(QColor(0,150,255)))
                for h in self._handle_rects(r): p.drawRect(h)
    def _hit_test(self,pos):
        for i in reversed(range(len(self.boxes))):
            r=self.image_to_widget_rect(self.boxes[i])
            for h,m in zip(self._handle_rects(r),["resize_tl","resize_tr","resize_bl","resize_br"]):
                if h.contains(pos): return i,m
            if r.contains(pos): return i,"move"
        return None,None
    def mousePressEvent(self,e):
        if self.pixmap is None or self.image_rgb is None or e.button()!=Qt.LeftButton: return
        pt=self.widget_to_image(e.position()); ih,iw=self.image_rgb.shape[:2]
        if pt.x()<0 or pt.y()<0 or pt.x()>iw or pt.y()>ih: return
        if self.add_mode:
            self.dragging=True; self.drag_mode="new"; self.new_box_start_img=pt; self.boxes.append(BoxData(str(len(self.boxes)+1),self.new_box_contact_id.strip(),self.new_box_label,float('nan'),pt.x(),pt.y(),1,1,"manual")); self.selected_index=len(self.boxes)-1; self.selectionChanged.emit(self.selected_index); self.update(); return
        idx,mode=self._hit_test(e.position()); self.selected_index=idx
        if idx is not None:
            self.selectionChanged.emit(idx); self.dragging=True; self.drag_mode=mode; self.drag_start_img=pt; self.original_box=BoxData(**self.boxes[idx].__dict__)
        else: self.selectionChanged.emit(-1)
        self.update()
    def mouseMoveEvent(self,e):
        if not self.dragging or self.selected_index is None or self.pixmap is None or self.image_rgb is None: return
        pt=self.widget_to_image(e.position()); ih,iw=self.image_rgb.shape[:2]; pt.setX(max(0,min(iw,pt.x()))); pt.setY(max(0,min(ih,pt.y()))); b=self.boxes[self.selected_index]
        if self.drag_mode=="new":
            x1=min(self.new_box_start_img.x(),pt.x()); y1=min(self.new_box_start_img.y(),pt.y()); x2=max(self.new_box_start_img.x(),pt.x()); y2=max(self.new_box_start_img.y(),pt.y()); b.x=x1; b.y=y1; b.w=max(1,x2-x1); b.h=max(1,y2-y1); b.source="manual"
        elif self.drag_mode=="move" and self.original_box:
            dx=pt.x()-self.drag_start_img.x(); dy=pt.y()-self.drag_start_img.y(); b.x=max(0,min(iw-b.w,self.original_box.x+dx)); b.y=max(0,min(ih-b.h,self.original_box.y+dy)); b.source=append_edited_suffix(b.source)
        elif self.drag_mode and self.drag_mode.startswith("resize") and self.original_box:
            x1=self.original_box.x; y1=self.original_box.y; x2=self.original_box.x+self.original_box.w; y2=self.original_box.y+self.original_box.h
            if self.drag_mode=="resize_tl": x1,y1=pt.x(),pt.y()
            elif self.drag_mode=="resize_tr": x2,y1=pt.x(),pt.y()
            elif self.drag_mode=="resize_bl": x1,y2=pt.x(),pt.y()
            elif self.drag_mode=="resize_br": x2,y2=pt.x(),pt.y()
            nx1=max(0,min(x1,x2-1)); ny1=max(0,min(y1,y2-1)); nx2=min(iw,max(x2,nx1+1)); ny2=min(ih,max(y2,ny1+1)); b.x=nx1; b.y=ny1; b.w=nx2-nx1; b.h=ny2-ny1; b.source=append_edited_suffix(b.source)
        self.boxesChanged.emit(); self.update()
    def mouseReleaseEvent(self,e):
        if self.dragging: self.dragging=False; self.drag_mode=None; self.original_box=None; self.boxesChanged.emit(); self.update()

class MaritimeReviewGUI(QMainWindow):
    def __init__(self,startup):
        super().__init__(); self.setWindowTitle("Maritime Labeling, Detection, and Tracking GUI"); self.resize(1550,900)
        self.input_type=startup.input_type; self.original_input_path=Path(startup.input_path); self.output_dir=Path(startup.output_path); self.video_frame_step=startup.video_frame_step; self.video_path=self.original_input_path if self.input_type=="video" else None; self.extracted_video_frame_dir=None; self.detector_mode=DETECTOR_MODE.lower().strip(); self.model=None; self.model_description="None"; self.box_color_mode=BOX_COLOR_MODE; self.frame_data=[]; self.current_index=0; self.current_image_rgb=None; self.known_contact_ids=[]
        self._prepare_input(); self._build_ui(); self._load_model(); self._load_images();
        if self.frame_data: self.load_frame(max(0,min(START_FRAME_INDEX-1,len(self.frame_data)-1)))
    def _prepare_input(self):
        if self.input_type=="images": self.input_dir=self.original_input_path; return
        self.extracted_video_frame_dir=Path.cwd()/f"ExtractedVideoFrames_{self.original_input_path.stem}"; self.extracted_video_frame_dir.mkdir(parents=True,exist_ok=True); extract_video_frames_for_review(self.original_input_path,self.extracted_video_frame_dir,self.video_frame_step); self.input_dir=self.extracted_video_frame_dir
    def _build_ui(self):
        c=QWidget(); self.setCentralWidget(c); ml=QHBoxLayout(c); ig=QGroupBox("Image Review"); il=QVBoxLayout(ig); self.canvas=ImageCanvas(); self.status_bar_label=QLabel("Ready"); il.addWidget(self.canvas); il.addWidget(self.status_bar_label)
        scroll=QScrollArea(); scroll.setWidgetResizable(True); cw=QWidget(); scroll.setWidget(cw); cl=QVBoxLayout(cw); cg=QGroupBox("Controls"); gl=QVBoxLayout(cg); cl.addWidget(cg)
        self.model_label=QLabel("Detector:"); self.model_label.setWordWrap(True); self.frame_label=QLabel("Frame:"); self.file_label=QLabel("File:"); self.file_label.setWordWrap(True); self.status_label=QLabel("Status:")
        for w in [self.model_label,self.frame_label,self.file_label,self.status_label]: gl.addWidget(w)
        jl=QHBoxLayout(); self.jump_spin=QSpinBox(); self.jump_spin.setMinimum(1); self.go_button=QPushButton("Go To Frame"); jl.addWidget(self.jump_spin); jl.addWidget(self.go_button); gl.addLayout(jl)
        for names in [("Previous","Next"),("Mark Good","Mark Bad"),("Add Box","Delete Selected"),(None,"Apply Label"),(None,"Apply ContactID"),(None,"Use Existing ID"),("Run/Reload Model","Clear Boxes")]: pass
        nav=QHBoxLayout(); self.prev_button=QPushButton("Previous"); self.next_button=QPushButton("Next"); nav.addWidget(self.prev_button); nav.addWidget(self.next_button); gl.addLayout(nav)
        rv=QHBoxLayout(); self.mark_good_button=QPushButton("Mark Good"); self.mark_bad_button=QPushButton("Mark Bad"); rv.addWidget(self.mark_good_button); rv.addWidget(self.mark_bad_button); gl.addLayout(rv); self.mark_unreviewed_button=QPushButton("Mark Unreviewed"); gl.addWidget(self.mark_unreviewed_button)
        ed=QHBoxLayout(); self.add_box_button=QPushButton("Add Box"); self.delete_button=QPushButton("Delete Selected"); ed.addWidget(self.add_box_button); ed.addWidget(self.delete_button); gl.addLayout(ed)
        lab=QHBoxLayout(); self.label_dropdown=QComboBox(); self.label_dropdown.addItems(MANUAL_LABELS); self.label_dropdown.setCurrentText(DEFAULT_MANUAL_LABEL); self.apply_label_button=QPushButton("Apply Label"); lab.addWidget(self.label_dropdown); lab.addWidget(self.apply_label_button); gl.addLayout(lab)
        co=QHBoxLayout(); self.contact_field=QLineEdit(DEFAULT_CONTACT_ID); self.contact_field.setPlaceholderText("Type ContactID"); self.apply_contact_button=QPushButton("Apply ContactID"); co.addWidget(self.contact_field); co.addWidget(self.apply_contact_button); gl.addLayout(co)
        ec=QHBoxLayout(); self.contact_dropdown=QComboBox(); self.contact_dropdown.addItem("<none>"); self.use_existing_contact_button=QPushButton("Use Existing ID"); ec.addWidget(self.contact_dropdown); ec.addWidget(self.use_existing_contact_button); gl.addLayout(ec)
        cm=QHBoxLayout(); self.color_dropdown=QComboBox(); self.color_dropdown.addItems(["label","contactID","source","single"]); self.color_dropdown.setCurrentText(self.box_color_mode); cm.addWidget(self.color_dropdown); cm.addWidget(QLabel("Saved Box Color Mode")); gl.addLayout(cm)
        mo=QHBoxLayout(); self.rerun_button=QPushButton("Run/Reload Model"); self.clear_button=QPushButton("Clear Boxes"); mo.addWidget(self.rerun_button); mo.addWidget(self.clear_button); gl.addLayout(mo)
        self.save_frame_button=QPushButton("Save Current Frame"); self.export_button=QPushButton("Export All Results"); gl.addWidget(self.save_frame_button); gl.addWidget(self.export_button)
        self.help_text=QTextEdit(); self.help_text.setReadOnly(True); self.help_text.setFixedHeight(130); self.help_text.setText("Instructions:\n1. Model boxes load automatically unless detector mode is none.\n2. Click a box or table row to select it.\n3. Drag/resize boxes on the image.\n4. Use Add Box to draw a missing object.\n5. Edit ObjectID, ContactID, and Label in the table.\n6. Use ContactID to track the same object across frames.\n7. Choose saved box color mode before exporting.\n8. Export All Results saves all frames, including empty frames."); gl.addWidget(self.help_text)
        self.box_table=QTableWidget(0,9); self.box_table.setMinimumHeight(250); self.box_table.setHorizontalHeaderLabels(["ObjectID","ContactID","Label","Confidence","X","Y","W","H","Source"]); self.box_table.setSelectionBehavior(QTableWidget.SelectRows); self.box_table.setSelectionMode(QTableWidget.SingleSelection); gl.addWidget(self.box_table)
        self.progress_label=QLabel("Reviewed: 0 / 0"); gl.addWidget(self.progress_label); self.save_next_button=QPushButton("Save && Next"); self.summary_button=QPushButton("Show ContactID Summary"); gl.addWidget(self.save_next_button); gl.addWidget(self.summary_button); gl.addStretch()
        ml.addWidget(ig,3); ml.addWidget(scroll,1)
        self.prev_button.clicked.connect(self.previous_frame); self.next_button.clicked.connect(self.next_frame); self.go_button.clicked.connect(self.go_to_frame); self.mark_good_button.clicked.connect(lambda:self.mark_frame("good")); self.mark_bad_button.clicked.connect(lambda:self.mark_frame("bad")); self.mark_unreviewed_button.clicked.connect(lambda:self.mark_frame("unreviewed")); self.add_box_button.clicked.connect(self.toggle_add_box_mode); self.delete_button.clicked.connect(self.delete_selected_box); self.apply_label_button.clicked.connect(self.apply_selected_label); self.apply_contact_button.clicked.connect(self.apply_selected_contact_id); self.use_existing_contact_button.clicked.connect(self.use_existing_contact_id); self.color_dropdown.currentTextChanged.connect(self.set_box_color_mode); self.rerun_button.clicked.connect(self.rerun_model); self.clear_button.clicked.connect(self.clear_boxes); self.save_frame_button.clicked.connect(self.save_current_frame); self.export_button.clicked.connect(self.export_all_results); self.save_next_button.clicked.connect(self.save_and_next); self.summary_button.clicked.connect(self.show_contact_id_summary); self.box_table.cellClicked.connect(self.table_cell_clicked); self.box_table.cellChanged.connect(self.table_cell_changed); self.canvas.selectionChanged.connect(self.canvas_selection_changed); self.canvas.boxesChanged.connect(self.refresh_table)
    def _load_model(self):
        if self.detector_mode=="none": self.model_description="None"; self.model_label.setText("Detector: None"); return
        if YOLO is None: QMessageBox.critical(self,"Ultralytics Import Error",f"Could not import ultralytics YOLO.\n\n{YOLO_IMPORT_ERROR}"); raise RuntimeError("ultralytics missing")
        if self.detector_mode=="pretrained": src=PRETRAINED_MODEL_NAME; self.model_description=f"Pretrained: {src}"
        elif self.detector_mode=="custom":
            if not CUSTOM_MODEL_PATH.exists(): raise FileNotFoundError(CUSTOM_MODEL_PATH)
            src=str(CUSTOM_MODEL_PATH); self.model_description=f"Custom: {CUSTOM_MODEL_PATH}"
        else: raise ValueError("bad detector mode")
        self.status_bar_label.setText(f"Loading detector: {src}"); QApplication.processEvents(); self.model=YOLO(src); self.model_label.setText(f"Detector: {self.model_description}")
    def _load_images(self):
        paths=find_images_recursive(self.input_dir); paths=paths[:int(MAX_IMAGES_TO_LOAD)] if MAX_IMAGES_TO_LOAD is not None else paths; self.frame_data=[FrameData(p) for p in paths]; self.jump_spin.setMaximum(max(1,len(self.frame_data))); self.status_bar_label.setText(f"Images loaded: {len(self.frame_data)}")
        if not self.frame_data: QMessageBox.warning(self,"No Images",f"No images found under:\n{self.input_dir}")
    def load_frame(self,index):
        if not self.frame_data: return
        self.current_index=max(0,min(index,len(self.frame_data)-1)); f=self.frame_data[self.current_index]; bgr=cv2.imread(str(f.image_path))
        if bgr is None: QMessageBox.warning(self,"Image Error",f"Could not read image:\n{f.image_path}"); return
        self.current_image_rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
        if not f.detected: self.run_detector_for_frame(self.current_index)
        self.canvas.set_image_and_boxes(self.current_image_rgb,f.boxes); self.refresh_ui_labels(); self.refresh_table()
    def run_detector_for_frame(self,index):
        f=self.frame_data[index]
        if self.detector_mode=="none" or self.model is None: f.boxes=[]; f.detected=True; return
        res=self.model.predict(source=str(f.image_path),conf=CONFIDENCE_THRESHOLD,verbose=False); boxes=[]
        if res and res[0].boxes is not None:
            names=res[0].names
            for b in res[0].boxes:
                xyxy=b.xyxy[0].cpu().numpy(); conf=float(b.conf[0].cpu().numpy()); cls=int(b.cls[0].cpu().numpy()); lab=str(names.get(cls,cls))
                if (not KEEP_ALL_DETECTED_CLASSES) and lab not in TARGET_CLASSES: continue
                x1,y1,x2,y2=xyxy; boxes.append(BoxData(str(len(boxes)+1),"",lab,conf,float(x1),float(y1),float(x2-x1),float(y2-y1),self.detector_mode))
        f.boxes=boxes; f.detected=True
    def refresh_ui_labels(self):
        f=self.frame_data[self.current_index]; self.model_label.setText(f"Detector: {self.model_description}"); self.frame_label.setText(f"Frame: {self.current_index+1} / {len(self.frame_data)}"); self.file_label.setText(f"File: {f.image_path.name}"); self.status_label.setText(f"Status: {f.frame_status} | Boxes: {len(f.boxes)}"); rc=sum(1 for x in self.frame_data if x.reviewed); self.progress_label.setText(f"Reviewed: {rc} / {len(self.frame_data)} | ContactIDs: {len(self.known_contact_ids)} | Saved color: {self.box_color_mode}"); self.status_bar_label.setText(f"Input: {self.input_type} | Frame {self.current_index+1}/{len(self.frame_data)} | {f.image_path} | Status: {f.frame_status}"); self.jump_spin.setValue(self.current_index+1)
    def refresh_table(self):
        if not self.frame_data: return
        f=self.frame_data[self.current_index]; self.box_table.blockSignals(True); self.box_table.setRowCount(len(f.boxes))
        for r,b in enumerate(f.boxes):
            vals=[b.object_id,b.contact_id,b.label,"" if math.isnan(b.confidence) else f"{b.confidence:.4f}",str(round(b.x)),str(round(b.y)),str(round(b.w)),str(round(b.h)),b.source]
            for c,v in enumerate(vals):
                it=QTableWidgetItem(v)
                if c not in [0,1,2]: it.setFlags(it.flags() & ~Qt.ItemIsEditable)
                self.box_table.setItem(r,c,it)
        self.box_table.blockSignals(False); self.refresh_ui_labels()
    def table_cell_clicked(self,r,c): self.canvas.set_selected_index(r); self.update_edit_fields_from_box(r)
    def table_cell_changed(self,r,c):
        f=self.frame_data[self.current_index]
        if r<0 or r>=len(f.boxes): return
        it=self.box_table.item(r,c); val=it.text().strip() if it else ""; b=f.boxes[r]
        if c==0: b.object_id=val
        elif c==1: b.contact_id=val; self.contact_field.setText(val); self.register_contact_id(val)
        elif c==2: b.label=val; self.label_dropdown.setCurrentText(val) if val in MANUAL_LABELS else None
        else: return
        b.source=append_edited_suffix(b.source); self.canvas.update(); self.refresh_table()
    def canvas_selection_changed(self,i):
        if i<0: self.box_table.clearSelection(); return
        self.box_table.selectRow(i); self.canvas.set_selected_index(i); self.update_edit_fields_from_box(i)
    def update_edit_fields_from_box(self,i):
        f=self.frame_data[self.current_index]
        if 0<=i<len(f.boxes):
            b=f.boxes[i]; self.contact_field.setText(b.contact_id); self.label_dropdown.setCurrentText(b.label) if b.label in MANUAL_LABELS else None
    def previous_frame(self): self.load_frame(self.current_index-1) if self.current_index>0 else None
    def next_frame(self): self.load_frame(self.current_index+1) if self.current_index<len(self.frame_data)-1 else None
    def go_to_frame(self): self.load_frame(self.jump_spin.value()-1)
    def mark_frame(self,status): f=self.frame_data[self.current_index]; f.frame_status=status; f.reviewed=status!="unreviewed"; self.refresh_ui_labels()
    def toggle_add_box_mode(self): en=not self.canvas.add_mode; self.canvas.set_add_mode(en,self.label_dropdown.currentText(),self.contact_field.text().strip()); self.add_box_button.setText("Cancel Add Box" if en else "Add Box")
    def delete_selected_box(self):
        idx=self.canvas.selected_index
        if idx is None: QMessageBox.information(self,"No Box Selected","Select a box first."); return
        f=self.frame_data[self.current_index]
        if 0<=idx<len(f.boxes): del f.boxes[idx]; assign_missing_object_ids(f.boxes); self.canvas.set_image_and_boxes(self.current_image_rgb,f.boxes); self.refresh_table()
    def apply_selected_label(self):
        idx=self.canvas.selected_index
        if idx is None: QMessageBox.information(self,"No Box Selected","Select a box first."); return
        f=self.frame_data[self.current_index]
        if 0<=idx<len(f.boxes): f.boxes[idx].label=self.label_dropdown.currentText(); f.boxes[idx].source=append_edited_suffix(f.boxes[idx].source)
        self.canvas.update(); self.refresh_table()
    def apply_selected_contact_id(self):
        idx=self.canvas.selected_index
        if idx is None: QMessageBox.information(self,"No Box Selected","Select a box first."); return
        cid=self.contact_field.text().strip(); f=self.frame_data[self.current_index]
        if 0<=idx<len(f.boxes): f.boxes[idx].contact_id=cid; f.boxes[idx].source=append_edited_suffix(f.boxes[idx].source); self.register_contact_id(cid)
        self.canvas.update(); self.refresh_table()
    def use_existing_contact_id(self):
        idx=self.canvas.selected_index; cid=self.contact_dropdown.currentText().strip()
        if idx is None: QMessageBox.information(self,"No Box Selected","Select a box first."); return
        if cid in ["","<none>"]: QMessageBox.information(self,"No ContactID Selected","Select an existing ContactID first."); return
        f=self.frame_data[self.current_index]
        if 0<=idx<len(f.boxes): f.boxes[idx].contact_id=cid; f.boxes[idx].source=append_edited_suffix(f.boxes[idx].source); self.contact_field.setText(cid)
        self.canvas.update(); self.refresh_table()
    def register_contact_id(self,cid):
        cid=str(cid).strip()
        if not cid or cid=="<none>": return
        if cid not in self.known_contact_ids: self.known_contact_ids.append(cid); self.update_contact_dropdown()
    def update_contact_dropdown(self):
        cur=self.contact_dropdown.currentText(); self.contact_dropdown.blockSignals(True); self.contact_dropdown.clear(); self.contact_dropdown.addItem("<none>"); [self.contact_dropdown.addItem(x) for x in self.known_contact_ids]; self.contact_dropdown.setCurrentText(cur) if cur in self.known_contact_ids else None; self.contact_dropdown.blockSignals(False)
    def set_box_color_mode(self,mode): self.box_color_mode=mode; self.refresh_ui_labels()
    def rerun_model(self):
        if self.detector_mode=="none" or self.model is None: QMessageBox.information(self,"No Model","Detector mode is set to none. No model will run."); return
        if QMessageBox.question(self,"Run Model","Run model again and replace current boxes?",QMessageBox.Yes|QMessageBox.No,QMessageBox.No)!=QMessageBox.Yes: return
        f=self.frame_data[self.current_index]; f.detected=False; self.run_detector_for_frame(self.current_index); self.canvas.set_image_and_boxes(self.current_image_rgb,f.boxes); self.refresh_table()
    def clear_boxes(self):
        if QMessageBox.question(self,"Clear Boxes","Remove all boxes from this frame?",QMessageBox.Yes|QMessageBox.No,QMessageBox.No)!=QMessageBox.Yes: return
        f=self.frame_data[self.current_index]; f.boxes=[]; self.canvas.set_image_and_boxes(self.current_image_rgb,f.boxes); self.refresh_table()
    def save_current_frame(self): self.frame_data[self.current_index].reviewed=True; self.export_one_frame(self.current_index); self.refresh_ui_labels(); QMessageBox.information(self,"Saved","Current frame exported.")
    def save_and_next(self):
        self.frame_data[self.current_index].reviewed=True; self.export_one_frame(self.current_index); self.refresh_ui_labels(); self.next_frame() if self.current_index<len(self.frame_data)-1 else QMessageBox.information(self,"Done","Last frame reached.")
    def export_all_results(self):
        if QMessageBox.question(self,"Export All Results","Export all frames to CSV, crops, pixels, and annotated images?",QMessageBox.Yes|QMessageBox.No,QMessageBox.Yes)!=QMessageBox.Yes: return
        rows=[]
        for i in range(len(self.frame_data)):
            if not self.frame_data[i].detected: self.run_detector_for_frame(i)
            rows.extend(self.export_one_frame(i,True))
        self.output_dir.mkdir(parents=True,exist_ok=True); csv=self.output_dir/"reviewed_detections_all.csv"; pd.DataFrame(rows).to_csv(csv,index=False); QMessageBox.information(self,"Export Complete",f"Export complete.\n\nCSV:\n{csv}")
    def export_one_frame(self,idx,return_rows=False):
        f=self.frame_data[idx]; bgr=cv2.imread(str(f.image_path));
        if bgr is None: return []
        ih,iw=bgr.shape[:2]; ad=self.output_dir/"reviewed_annotated"; cd=self.output_dir/"reviewed_crops"; pdx=self.output_dir/"reviewed_pixels"; [d.mkdir(parents=True,exist_ok=True) for d in [ad,cd,pdx]]; base=f.image_path.stem; ub=f"{idx+1:06d}_{base}"; ann_file=ad/f"{ub}_reviewed.png"; ann=bgr.copy(); rows=[]
        for j,b in enumerate(f.boxes,1):
            if not b.has_valid_position(): continue
            x1,y1,x2,y2=b.as_xyxy_int(iw,ih); fw=x2-x1+1; fh=y2-y1+1
            if fw<=1 or fh<=1: continue
            area=fw*fh; center_x=x1+fw/2; center_y=y1+fh/2; nw=fw/iw; nh=fh/ih; ncx=center_x/iw; ncy=center_y/ih; crop=bgr[y1:y2+1,x1:x2+1]; crop_file=cd/f"{ub}_object_{j}_{make_safe_filename(b.label)}.png"; pix_file=pdx/f"{ub}_object_{j}_pixels.npz"; cv2.imwrite(str(crop_file),crop); xs,ys=np.meshgrid(np.arange(x1,x2+1),np.arange(y1,y2+1)); np.savez_compressed(pix_file,pixelCoords=np.column_stack([xs.ravel(),ys.ravel()]),x1=x1,y1=y1,x2=x2,y2=y2,finalW=fw,finalH=fh,areaPixels=area,centerX=center_x,centerY=center_y,normCenterX=ncx,normCenterY=ncy,normWidth=nw,normHeight=nh,objectCrop=crop)
            rgb=get_box_color(b,self.box_color_mode); bgrc=(rgb[2],rgb[1],rgb[0]); cv2.rectangle(ann,(x1,y1),(x2,y2),bgrc,2); cv2.putText(ann,make_export_label_text(b),(x1,max(20,y1-8)),cv2.FONT_HERSHEY_SIMPLEX,0.55,bgrc,2)
            rows.append({"Frame":base,"FullPath":str(f.image_path),"FrameIndex":idx+1,"ObjectID":b.object_id,"ContactID":b.contact_id,"Label":b.label,"Confidence":None if math.isnan(b.confidence) else b.confidence,"Source":b.source,"FrameStatus":f.frame_status,"Reviewed":f.reviewed,"X1":x1,"Y1":y1,"X2":x2,"Y2":y2,"Width":fw,"Height":fh,"AreaPixels":area,"SizeCategory":classify_object_size(fw,fh),"CenterX":center_x,"CenterY":center_y,"NormCenterX":ncx,"NormCenterY":ncy,"NormWidth":nw,"NormHeight":nh,"CropFile":str(crop_file),"PixelFile":str(pix_file),"ImageWidth":iw,"ImageHeight":ih,"AnnotatedImage":str(ann_file),"DetectorDescription":self.model_description,"BoxColorMode":self.box_color_mode,"BoxColorR":rgb[0],"BoxColorG":rgb[1],"BoxColorB":rgb[2]})
        cv2.imwrite(str(ann_file),ann)
        if not rows and EXPORT_EMPTY_FRAME_ROWS: rows.append({"Frame":base,"FullPath":str(f.image_path),"FrameIndex":idx+1,"ObjectID":"","ContactID":"","Label":"none","Confidence":None,"Source":"none","FrameStatus":f.frame_status,"Reviewed":f.reviewed,"X1":None,"Y1":None,"X2":None,"Y2":None,"Width":None,"Height":None,"AreaPixels":None,"SizeCategory":"none","CenterX":None,"CenterY":None,"NormCenterX":None,"NormCenterY":None,"NormWidth":None,"NormHeight":None,"CropFile":"","PixelFile":"","ImageWidth":iw,"ImageHeight":ih,"AnnotatedImage":str(ann_file),"DetectorDescription":self.model_description,"BoxColorMode":self.box_color_mode,"BoxColorR":None,"BoxColorG":None,"BoxColorB":None})
        pd.DataFrame(rows).to_csv(self.output_dir/f"{ub}_reviewed.csv",index=False); return rows
    def show_contact_id_summary(self):
        if not self.known_contact_ids: QMessageBox.information(self,"ContactID Summary","Known ContactIDs:\n\nNone"); return
        lines=["Known ContactIDs:",""]
        for cid in self.known_contact_ids:
            info=self.get_contact_id_summary_info(cid); lines += [str(cid),f"  Boxes: {info['box_count']}",f"  Frames: {info['frame_list_text']}",f"  First frame: {info['first_frame_text']}",f"  Last frame: {info['last_frame_text']}",f"  Labels: {info['label_list_text']}",""]
        QMessageBox.information(self,"ContactID Summary","\n".join(lines))
    def get_contact_id_summary_info(self,cid):
        frames=[]; labels=[]; count=0
        for fi,f in enumerate(self.frame_data,1):
            hit=False
            for b in f.boxes:
                if b.contact_id==cid: count+=1; hit=True; labels.append(b.label)
            if hit: frames.append(fi)
        return {"box_count":count,"frame_list_text":compact_frame_list(frames) if frames else "none","first_frame_text":str(min(frames)) if frames else "none","last_frame_text":str(max(frames)) if frames else "none","label_list_text":", ".join(sorted(set(labels))) if labels else "none"}

def extract_video_frames_for_review(video_path,out_dir,step):
    cap=cv2.VideoCapture(str(video_path));
    if not cap.isOpened(): raise RuntimeError(f"Could not open video: {video_path}")
    raw=1; saved=1
    while True:
        ok,frame=cap.read()
        if not ok: break
        if (raw-1)%step==0: cv2.imwrite(str(out_dir/f"frame_{saved:06d}_raw_{raw:06d}.jpg"),frame); saved+=1
        raw+=1
    cap.release(); print(f"Extracted {saved-1} review frames from {raw-1} video frames.")
def find_images_recursive(root): return sorted([p for p in Path(root).rglob("*") if p.is_file() and p.suffix.lower() in {".jpg",".jpeg",".png",".bmp",".tif",".tiff"}])
def append_edited_suffix(s): s=str(s); return s if "_edited" in s else s+"_edited"
def assign_missing_object_ids(boxes):
    for i,b in enumerate(boxes,1):
        if not str(b.object_id).strip(): b.object_id=str(i)
def make_roi_label(b):
    parts=[]
    if str(b.label).strip() and str(b.label).strip()!="none": parts.append(str(b.label).strip())
    if str(b.contact_id).strip(): parts.append(f"CID:{b.contact_id.strip()}")
    return " | ".join(parts) if parts else "object"
def make_export_label_text(b):
    parts=[]
    if str(b.label).strip() and str(b.label).strip()!="none": parts.append(str(b.label).strip())
    if str(b.object_id).strip(): parts.append(f"ID:{b.object_id.strip()}")
    if str(b.contact_id).strip(): parts.append(f"CID:{b.contact_id.strip()}")
    parts.append("manual" if math.isnan(b.confidence) else f"{b.confidence:.2f}"); return " | ".join(parts) if parts else "object"
def deterministic_color_from_string(v):
    h=int(hashlib.md5(str(v).encode()).hexdigest(),16); hsv=np.uint8([[[int((h%360)/360*179),190,255]]]); rgb=cv2.cvtColor(hsv,cv2.COLOR_HSV2RGB)[0,0]; return int(rgb[0]),int(rgb[1]),int(rgb[2])
def get_box_color(b,mode):
    m=str(mode).lower()
    if m=="label": return LABEL_COLOR_MAP.get(b.label,DEFAULT_BOX_COLOR)
    if m=="source": return SOURCE_COLOR_MAP.get(b.source,DEFAULT_BOX_COLOR)
    if m=="contactid": return deterministic_color_from_string(b.contact_id) if b.contact_id.strip() else DEFAULT_BOX_COLOR
    return DEFAULT_BOX_COLOR
def classify_object_size(w,h):
    a=w*h
    return "tiny" if a<32*32 else "small" if a<96*96 else "medium" if a<224*224 else "large"
def make_safe_filename(label):
    s=str(label)
    for ch in [' ','/','\\',':','*','?','"','<','>','|']: s=s.replace(ch,'_')
    return s
def compact_frame_list(nums):
    vals=sorted(set(nums))
    if not vals: return "none"
    ranges=[]; start=prev=vals[0]
    for v in vals[1:]:
        if v==prev+1: prev=v
        else: ranges.append(str(start) if start==prev else f"{start}-{prev}"); start=prev=v
    ranges.append(str(start) if start==prev else f"{start}-{prev}"); return ", ".join(ranges)
def main():
    app=QApplication(sys.argv); startup=StartupDialog()
    if startup.exec()!=QDialog.Accepted: return
    win=MaritimeReviewGUI(startup); win.show(); sys.exit(app.exec())
if __name__=="__main__": main()
