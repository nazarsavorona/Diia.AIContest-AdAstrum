"""
Step 3: Face detection and landmarks using MediaPipe
"""

from typing import Dict, Any, List, Tuple
import numpy as np
import cv2
import mediapipe as mp

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
from app.utils.image_utils import convert_bgr_to_rgb
import config


class FaceDetectionValidator(BaseValidator):
    """Detects faces and extracts landmarks using MediaPipe"""
    
    def __init__(self):
        super().__init__()
        # Initialize MediaPipe Face Detection
        self.mp_face_detection = mp.solutions.face_detection
        self.face_detection = self.mp_face_detection.FaceDetection(
            min_detection_confidence=config.MEDIAPIPE_MIN_DETECTION_CONFIDENCE,
            model_selection=1  # 1 for full-range model (better for photos)
        )
        
        # Initialize MediaPipe Face Mesh for landmarks
        self.mp_face_mesh = mp.solutions.face_mesh
        self.face_mesh = self.mp_face_mesh.FaceMesh(
            static_image_mode=True,
            max_num_faces=config.MEDIAPIPE_MAX_NUM_FACES,
            min_detection_confidence=config.MEDIAPIPE_MIN_DETECTION_CONFIDENCE,
            min_tracking_confidence=config.MEDIAPIPE_MIN_TRACKING_CONFIDENCE
        )
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Detect faces and extract landmarks
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Optional context
            
        Returns:
            ValidationResult with face data in metadata
        """
        result = self._create_result()
        
        # Convert BGR to RGB for MediaPipe
        image_rgb = convert_bgr_to_rgb(image)
        h, w = image.shape[:2]
        
        # Detect faces
        detection_results = self.face_detection.process(image_rgb)
        
        # Check number of faces
        if detection_results.detections is None or len(detection_results.detections) == 0:
            result.add_error(ErrorCode.NO_FACE_DETECTED)
            return result
        
        if len(detection_results.detections) > 1:
            result.add_error(
                ErrorCode.MULTIPLE_FACES,
                f"Detected {len(detection_results.detections)} faces"
            )
            return result
        
        # Get the face detection
        detection = detection_results.detections[0]
        
        # Extract bounding box
        bbox = self._get_bounding_box(detection, w, h)
        
        # Get landmarks using Face Mesh
        mesh_results = self.face_mesh.process(image_rgb)
        
        landmarks = None
        landmarks_3d = None
        if mesh_results.multi_face_landmarks:
            # Get landmarks for the first (and should be only) face
            face_landmarks = mesh_results.multi_face_landmarks[0]
            landmarks = self._extract_landmarks_2d(face_landmarks, w, h)
            landmarks_3d = self._extract_landmarks_3d(face_landmarks, w, h)
        
        # Store face data in metadata
        result.metadata = {
            'face_detected': True,
            'face_count': 1,
            'face_bbox': bbox,
            'landmarks': landmarks,
            'landmarks_3d': landmarks_3d,
            'detection_confidence': detection.score[0] if detection.score else None
        }
        
        return result
    
    def _get_bounding_box(self, detection, image_width: int, image_height: int) -> Tuple[int, int, int, int]:
        """
        Extract bounding box from MediaPipe detection
        
        Returns:
            Tuple of (x, y, width, height) in pixels
        """
        bbox = detection.location_data.relative_bounding_box
        
        x = int(bbox.xmin * image_width)
        y = int(bbox.ymin * image_height)
        w = int(bbox.width * image_width)
        h = int(bbox.height * image_height)
        
        # Ensure coordinates are within image bounds
        x = max(0, x)
        y = max(0, y)
        w = min(w, image_width - x)
        h = min(h, image_height - y)
        
        return (x, y, w, h)
    
    def _extract_landmarks_2d(self, face_landmarks, image_width: int, image_height: int) -> List[Dict]:
        """
        Extract 2D landmarks from MediaPipe Face Mesh
        
        Returns:
            List of landmark dictionaries with 'x', 'y' coordinates
        """
        landmarks = []
        for landmark in face_landmarks.landmark:
            landmarks.append({
                'x': landmark.x * image_width,
                'y': landmark.y * image_height
            })
        return landmarks
    
    def _extract_landmarks_3d(self, face_landmarks, image_width: int, image_height: int) -> List[Dict]:
        """
        Extract 3D landmarks from MediaPipe Face Mesh
        
        Returns:
            List of landmark dictionaries with 'x', 'y', 'z' coordinates
        """
        landmarks = []
        for landmark in face_landmarks.landmark:
            landmarks.append({
                'x': landmark.x * image_width,
                'y': landmark.y * image_height,
                'z': landmark.z * image_width  # z is relative to x
            })
        return landmarks
    
    def __del__(self):
        """Clean up MediaPipe resources"""
        if hasattr(self, 'face_detection'):
            self.face_detection.close()
        if hasattr(self, 'face_mesh'):
            self.face_mesh.close()
