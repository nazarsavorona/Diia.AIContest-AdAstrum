"""
Step 5: Face geometry checks (size, centering, occlusion)
"""

from typing import Dict, Any
import numpy as np
import cv2

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
import config


class GeometryValidator(BaseValidator):
    """Validates face geometry: size, centering, and occlusion"""
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Validate face geometry
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Must contain 'face_bbox' and 'landmarks' from face detection step
            
        Returns:
            ValidationResult
        """
        result = self._create_result()
        
        # Check if we have face data
        if not context or 'face_bbox' not in context:
            result.add_error(
                ErrorCode.NO_FACE_DETECTED,
                "Cannot check geometry: no face bounding box available"
            )
            return result
        
        bbox = context['face_bbox']
        h, w = image.shape[:2]
        
        # Check face size
        face_size_ratio = self._check_face_size(bbox, w, h, result)
        
        # Check face centering
        center_offset = self._check_face_centering(bbox, w, h, result)
        
        # Check for hair occlusion (if landmarks available)
        occlusion_score = 0.0
        if 'landmarks' in context and context['landmarks']:
            occlusion_score = self._check_hair_occlusion(
                image, bbox, context['landmarks'], result
            )
        
        # Store geometry data in metadata
        result.metadata = {
            'face_size_ratio': float(face_size_ratio),
            'center_offset_x': float(center_offset[0]),
            'center_offset_y': float(center_offset[1]),
            'occlusion_score': float(occlusion_score)
        }
        
        return result
    
    def _check_face_size(self, bbox: tuple, img_width: int, img_height: int, result: ValidationResult) -> float:
        """
        Check if face size is within acceptable range
        
        Returns:
            Face size ratio
        """
        x, y, w, h = bbox
        face_area = w * h
        image_area = img_width * img_height
        face_ratio = face_area / image_area
        
        if face_ratio < config.MIN_FACE_AREA_RATIO:
            result.add_error(
                ErrorCode.FACE_TOO_SMALL,
                f"Face occupies only {face_ratio * 100:.1f}% of frame (min: {config.MIN_FACE_AREA_RATIO * 100:.1f}%)"
            )
        
        if face_ratio > config.MAX_FACE_AREA_RATIO:
            result.add_error(
                ErrorCode.FACE_TOO_CLOSE,
                f"Face occupies {face_ratio * 100:.1f}% of frame (max: {config.MAX_FACE_AREA_RATIO * 100:.1f}%)"
            )
        
        return face_ratio
    
    def _check_face_centering(self, bbox: tuple, img_width: int, img_height: int, result: ValidationResult) -> tuple:
        """
        Check if face is centered in the frame
        
        Returns:
            Tuple of (x_offset, y_offset) as fractions of image dimensions
        """
        x, y, w, h = bbox
        
        # Calculate face center
        face_center_x = x + w / 2
        face_center_y = y + h / 2
        
        # Calculate image center
        img_center_x = img_width / 2
        img_center_y = img_height / 2
        
        # Calculate offset as fraction of image dimensions
        offset_x = abs(face_center_x - img_center_x) / img_width
        offset_y = abs(face_center_y - img_center_y) / img_height
        
        # Check if within tolerance
        if offset_x > config.FACE_CENTER_TOLERANCE or offset_y > config.FACE_CENTER_TOLERANCE:
            result.add_error(
                ErrorCode.FACE_NOT_CENTERED,
                f"Face is off-center (offset: {offset_x * 100:.1f}%, {offset_y * 100:.1f}%)"
            )
        
        return (offset_x, offset_y)
    
    def _check_hair_occlusion(self, image: np.ndarray, bbox: tuple, landmarks: list, result: ValidationResult) -> float:
        """
        Check if hair covers part of the face using edge detection around jawline
        
        This is a simplified heuristic approach that looks for strong edges
        near jawline landmarks which might indicate hair crossing the face boundary.
        
        Returns:
            Occlusion score (higher = more occlusion)
        """
        try:
            # Extract jawline landmark indices (MediaPipe Face Mesh)
            # Jawline contour landmarks: 10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109
            jawline_indices = [
                10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288,
                397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136,
                172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109
            ]
            
            # Convert to grayscale
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            
            # Apply edge detection
            edges = cv2.Canny(gray, 50, 150)
            
            # Check edge density near jawline landmarks
            occlusion_score = 0.0
            valid_points = 0
            
            for idx in jawline_indices:
                if idx < len(landmarks):
                    lm = landmarks[idx]
                    x, y = int(lm['x']), int(lm['y'])
                    
                    # Sample a small region around each landmark
                    margin = 10
                    y1 = max(0, y - margin)
                    y2 = min(edges.shape[0], y + margin)
                    x1 = max(0, x - margin)
                    x2 = min(edges.shape[1], x + margin)
                    
                    if y2 > y1 and x2 > x1:
                        region = edges[y1:y2, x1:x2]
                        edge_density = np.sum(region > 0) / region.size
                        occlusion_score += edge_density
                        valid_points += 1
            
            if valid_points > 0:
                occlusion_score /= valid_points
            
            # Threshold for hair occlusion
            # This is a simple heuristic - high edge density near jawline suggests hair
            if occlusion_score > config.HAIR_OCCLUSION_THRESHOLD:
                result.add_error(
                    ErrorCode.HAIR_COVERS_FACE,
                    f"Possible hair occlusion detected (score: {occlusion_score:.3f})"
                )
            
            return occlusion_score
            
        except Exception as e:
            # If occlusion check fails, don't fail the entire validation
            return 0.0
