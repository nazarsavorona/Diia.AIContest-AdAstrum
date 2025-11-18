"""
Step 4: Head pose and gaze estimation using PnP
"""

from typing import Dict, Any, Tuple
import numpy as np
import cv2

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
import config


class PoseEstimationValidator(BaseValidator):
    """Estimates head pose using PnP algorithm"""
    
    def __init__(self):
        super().__init__()
        
        # 3D model points (generic face model in cm)
        # These are approximate positions of facial landmarks in 3D space
        self.model_points = np.array([
            (0.0, 0.0, 0.0),            # Nose tip
            (0.0, -330.0, -65.0),       # Chin
            (-225.0, 170.0, -135.0),    # Left eye left corner
            (225.0, 170.0, -135.0),     # Right eye right corner
            (-150.0, -150.0, -125.0),   # Left mouth corner
            (150.0, -150.0, -125.0)     # Right mouth corner
        ], dtype=np.float64)
        
        # MediaPipe Face Mesh landmark indices for the above points
        self.landmark_indices = [
            1,      # Nose tip
            152,    # Chin
            263,    # Left eye left corner
            33,     # Right eye right corner
            287,    # Left mouth corner
            57      # Right mouth corner
        ]
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Estimate head pose
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Must contain 'landmarks' from face detection step
            
        Returns:
            ValidationResult with pose angles in metadata
        """
        result = self._create_result()
        
        # Check if we have landmarks
        if not context or 'landmarks' not in context or context['landmarks'] is None:
            result.add_error(
                ErrorCode.NO_FACE_DETECTED,
                "Cannot estimate pose: no face landmarks available"
            )
            return result
        
        landmarks = context['landmarks']
        h, w = image.shape[:2]
        
        # Extract image points for pose estimation
        try:
            image_points = self._get_image_points(landmarks)
        except Exception as e:
            result.add_error(
                ErrorCode.NO_FACE_DETECTED,
                f"Failed to extract landmarks for pose estimation: {str(e)}"
            )
            return result
        
        # Camera matrix (assuming focal length = image width)
        focal_length = w
        center = (w / 2, h / 2)
        camera_matrix = np.array([
            [focal_length, 0, center[0]],
            [0, focal_length, center[1]],
            [0, 0, 1]
        ], dtype=np.float64)
        
        # Assuming no lens distortion
        dist_coeffs = np.zeros((4, 1))
        
        # Solve PnP
        success, rotation_vector, translation_vector = cv2.solvePnP(
            self.model_points,
            image_points,
            camera_matrix,
            dist_coeffs,
            flags=cv2.SOLVEPNP_ITERATIVE
        )
        
        if not success:
            result.add_error(
                ErrorCode.FACE_NOT_STRAIGHT,
                "Failed to estimate head pose"
            )
            return result
        
        # Convert rotation vector to euler angles
        yaw, pitch, roll = self._rotation_vector_to_euler_angles(rotation_vector)
        
        # Check pose thresholds
        self._check_pose_angles(yaw, pitch, roll, result)
        
        # Store pose data in metadata
        result.metadata = {
            'yaw': float(yaw),
            'pitch': float(pitch),
            'roll': float(roll),
            'rotation_vector': rotation_vector.tolist(),
            'translation_vector': translation_vector.tolist()
        }
        
        return result
    
    def _get_image_points(self, landmarks: list) -> np.ndarray:
        """
        Extract specific landmark points for pose estimation
        
        Args:
            landmarks: List of all face landmarks
            
        Returns:
            numpy array of 2D points
        """
        image_points = []
        for idx in self.landmark_indices:
            if idx < len(landmarks):
                lm = landmarks[idx]
                image_points.append([lm['x'], lm['y']])
            else:
                raise ValueError(f"Landmark index {idx} out of range")
        
        return np.array(image_points, dtype=np.float64)
    
    def _rotation_vector_to_euler_angles(self, rotation_vector: np.ndarray) -> Tuple[float, float, float]:
        """
        Convert rotation vector to Euler angles (yaw, pitch, roll)
        
        Returns:
            Tuple of (yaw, pitch, roll) in degrees
        """
        # Convert rotation vector to rotation matrix
        rotation_matrix, _ = cv2.Rodrigues(rotation_vector)
        
        # Extract Euler angles from rotation matrix
        # Using the convention: R = Rz(yaw) * Ry(pitch) * Rx(roll)
        sy = np.sqrt(rotation_matrix[0, 0] ** 2 + rotation_matrix[1, 0] ** 2)
        
        singular = sy < 1e-6
        
        if not singular:
            roll = np.arctan2(rotation_matrix[2, 1], rotation_matrix[2, 2])
            pitch = np.arctan2(-rotation_matrix[2, 0], sy)
            yaw = np.arctan2(rotation_matrix[1, 0], rotation_matrix[0, 0])
        else:
            roll = np.arctan2(-rotation_matrix[1, 2], rotation_matrix[1, 1])
            pitch = np.arctan2(-rotation_matrix[2, 0], sy)
            yaw = 0
        
        # Convert to degrees
        roll = np.degrees(roll)
        pitch = np.degrees(pitch)
        yaw = np.degrees(yaw)
        
        return yaw, pitch, roll
    
    def _check_pose_angles(self, yaw: float, pitch: float, roll: float, result: ValidationResult):
        """
        Check if pose angles are within acceptable thresholds
        """
        # Check yaw (left/right rotation)
        if abs(yaw) > config.MAX_YAW:
            result.add_error(
                ErrorCode.FACE_NOT_STRAIGHT,
                f"Head is turned {abs(yaw):.1f}° (max: {config.MAX_YAW}°)"
            )
        
        # Check pitch (up/down tilt)
        if abs(pitch) > config.MAX_PITCH:
            result.add_error(
                ErrorCode.FACE_NOT_STRAIGHT,
                f"Head is tilted up/down {abs(pitch):.1f}° (max: {config.MAX_PITCH}°)"
            )
        
        # Check roll (head tilt)
        if abs(roll) > config.MAX_ROLL:
            result.add_error(
                ErrorCode.HEAD_TILTED,
                f"Head is tilted {abs(roll):.1f}° (max: {config.MAX_ROLL}°)"
            )
