"""
Error codes and messages for validation failures
"""

from typing import Dict, List
from enum import Enum


class ErrorCode(str, Enum):
    """Enumeration of all possible error codes"""
    
    # Step 1: Format and resolution errors
    WRONG_ASPECT_RATIO = "wrong_aspect_ratio"
    RESOLUTION_TOO_LOW = "resolution_too_low"
    UNSUPPORTED_FORMAT = "unsupported_file_format"
    LOW_QUALITY = "low_quality_or_too_compressed"
    
    # Step 2: Quality errors
    INSUFFICIENT_LIGHTING = "insufficient_lighting"
    OVEREXPOSED = "overexposed_or_too_bright"
    STRONG_SHADOWS = "strong_shadows_on_face"
    IMAGE_BLURRY = "image_blurry_or_out_of_focus"
    LOW_CONTRAST = "low_contrast"
    
    # Step 3: Face detection errors
    NO_FACE_DETECTED = "no_face_detected"
    MULTIPLE_FACES = "more_than_one_person_in_photo"
    
    # Step 4: Pose errors
    HEAD_TILTED = "head_is_tilted"
    FACE_NOT_STRAIGHT = "face_not_looking_straight_at_camera"
    
    # Step 5: Geometry errors
    FACE_TOO_SMALL = "face_too_small_in_frame"
    FACE_TOO_CLOSE = "face_too_close_or_cropped"
    FACE_NOT_CENTERED = "face_not_centered"
    HAIR_COVERS_FACE = "hair_covers_part_of_face"
    
    # Step 6: Background errors
    BACKGROUND_NOT_UNIFORM = "background_not_uniform"
    EXTRANEOUS_PEOPLE = "extraneous_people_in_background"
    EXTRANEOUS_OBJECTS = "extraneous_objects_in_background"
    
    # Step 7: Accessories and filters
    ACCESSORIES_DETECTED = "accessories_detected"
    FILTERS_DETECTED = "filters_or_heavy_editing_detected"


ERROR_MESSAGES: Dict[ErrorCode, str] = {
    # Format
    ErrorCode.WRONG_ASPECT_RATIO: "Image must have a 2:3 aspect ratio (portrait orientation)",
    ErrorCode.RESOLUTION_TOO_LOW: "Image resolution is too low. Minimum 600px required",
    ErrorCode.UNSUPPORTED_FORMAT: "Only JPEG and PNG formats are supported",
    ErrorCode.LOW_QUALITY: "Image quality is too low or heavily compressed",
    
    # Quality
    ErrorCode.INSUFFICIENT_LIGHTING: "Insufficient lighting. Please take photo in better lighting",
    ErrorCode.OVEREXPOSED: "Image is overexposed or too bright",
    ErrorCode.STRONG_SHADOWS: "Strong shadows detected on face. Use even lighting",
    ErrorCode.IMAGE_BLURRY: "Image is blurry or out of focus",
    ErrorCode.LOW_CONTRAST: "Image has very low contrast",
    
    # Face
    ErrorCode.NO_FACE_DETECTED: "No face detected in the image",
    ErrorCode.MULTIPLE_FACES: "More than one person detected in the photo",
    
    # Pose
    ErrorCode.HEAD_TILTED: "Head is tilted. Please keep your head straight",
    ErrorCode.FACE_NOT_STRAIGHT: "Please look straight at the camera",
    
    # Geometry
    ErrorCode.FACE_TOO_SMALL: "Face is too small in the frame. Move closer to the camera",
    ErrorCode.FACE_TOO_CLOSE: "Face is too close or cropped. Move back slightly",
    ErrorCode.FACE_NOT_CENTERED: "Face is not centered. Adjust camera position",
    ErrorCode.HAIR_COVERS_FACE: "Hair covers part of the face. Please move hair away from face",
    
    # Background
    ErrorCode.BACKGROUND_NOT_UNIFORM: "Background is not uniform. Use a plain background",
    ErrorCode.EXTRANEOUS_PEOPLE: "Additional people detected in background",
    ErrorCode.EXTRANEOUS_OBJECTS: "Extraneous objects detected in background",
    
    # Accessories
    ErrorCode.ACCESSORIES_DETECTED: "Accessories detected (glasses, hat, etc.). Please remove them",
    ErrorCode.FILTERS_DETECTED: "Filters or heavy editing detected. Use original unedited photo",
}


class ValidationError:
    """Represents a validation error with code and message"""
    
    def __init__(self, code: ErrorCode, custom_message: str = None):
        self.code = code
        self.message = custom_message or ERROR_MESSAGES.get(code, "Unknown error")
    
    def to_dict(self) -> Dict:
        return {
            "code": self.code.value,
            "message": self.message
        }


class ValidationResult:
    """Result of a validation step"""
    
    def __init__(self, passed: bool = True, errors: List[ValidationError] = None, metadata: Dict = None):
        self.passed = passed
        self.errors = errors or []
        self.metadata = metadata or {}
    
    def add_error(self, code: ErrorCode, message: str = None):
        """Add an error to the result"""
        self.passed = False
        self.errors.append(ValidationError(code, message))
    
    def to_dict(self) -> Dict:
        return {
            "passed": self.passed,
            "errors": [error.to_dict() for error in self.errors],
            "metadata": self.metadata
        }
