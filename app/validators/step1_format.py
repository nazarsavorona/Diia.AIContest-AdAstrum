"""
Step 1: Format, aspect ratio, and resolution validation
"""

import io
from typing import Dict, Any
import numpy as np
from PIL import Image
import cv2

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
from app.utils.image_utils import get_image_dimensions, calculate_aspect_ratio
import config


class FormatValidator(BaseValidator):
    """Validates image format, aspect ratio, and resolution"""
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Validate image format requirements
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Must contain 'image_bytes' for format detection
            
        Returns:
            ValidationResult
        """
        result = self._create_result()
        
        # Get image dimensions
        height, width = get_image_dimensions(image)
        
        # Check format (if image_bytes provided in context)
        if context and 'image_bytes' in context:
            image_format = self._check_format(context['image_bytes'], result)
            if image_format == 'JPEG':
                self._check_jpeg_quality(context['image_bytes'], result)
        
        # Check aspect ratio
        self._check_aspect_ratio(width, height, result)
        
        # Check resolution
        self._check_resolution(width, height, result)
        
        # Add metadata
        result.metadata = {
            'width': width,
            'height': height,
            'aspect_ratio': calculate_aspect_ratio(width, height),
            'min_dimension': min(width, height),
            'max_dimension': max(width, height)
        }
        
        return result
    
    def _check_format(self, image_bytes: bytes, result: ValidationResult) -> str:
        """Check if image format is supported"""
        try:
            pil_image = Image.open(io.BytesIO(image_bytes))
            image_format = pil_image.format
            
            if image_format not in config.ALLOWED_FORMATS:
                result.add_error(
                    ErrorCode.UNSUPPORTED_FORMAT,
                    f"Format {image_format} not supported. Use JPEG or PNG."
                )
            
            return image_format
        except Exception as e:
            result.add_error(ErrorCode.UNSUPPORTED_FORMAT, f"Could not determine image format: {str(e)}")
            return None
    
    def _check_aspect_ratio(self, width: int, height: int, result: ValidationResult):
        """Check if aspect ratio is close to 2:3"""
        aspect_ratio = calculate_aspect_ratio(width, height)
        target = config.TARGET_ASPECT_RATIO
        tolerance = config.ASPECT_RATIO_TOLERANCE
        
        # Check if within tolerance
        if not (target - tolerance <= aspect_ratio <= target + tolerance):
            result.add_error(
                ErrorCode.WRONG_ASPECT_RATIO,
                f"Aspect ratio {aspect_ratio:.2f} is outside acceptable range "
                f"({target - tolerance:.2f} - {target + tolerance:.2f})"
            )
    
    def _check_resolution(self, width: int, height: int, result: ValidationResult):
        """Check if resolution meets minimum requirements"""
        min_dim = min(width, height)
        
        if min_dim < config.MIN_RESOLUTION:
            result.add_error(
                ErrorCode.RESOLUTION_TOO_LOW,
                f"Minimum dimension {min_dim}px is below required {config.MIN_RESOLUTION}px"
            )
    
    def _check_jpeg_quality(self, image_bytes: bytes, result: ValidationResult):
        """
        Check JPEG quality by analyzing blockiness artifacts
        Uses DCT-based blockiness detection
        """
        try:
            # Decode image
            nparr = np.frombuffer(image_bytes, np.uint8)
            img = cv2.imdecode(nparr, cv2.IMREAD_GRAYSCALE)
            
            if img is None:
                return
            
            # Compute blockiness metric
            # Calculate variance between 8x8 blocks (JPEG compression blocks)
            blockiness = self._calculate_blockiness(img)
            
            if blockiness > config.JPEG_BLOCKINESS_THRESHOLD:
                result.add_error(
                    ErrorCode.LOW_QUALITY,
                    f"Image appears heavily compressed (blockiness: {blockiness:.2f})"
                )
                
        except Exception:
            # If we can't check quality, don't fail validation
            pass
    
    def _calculate_blockiness(self, gray_image: np.ndarray) -> float:
        """
        Calculate blockiness metric based on edge differences at 8x8 block boundaries
        Higher values indicate more blockiness (compression artifacts)
        """
        h, w = gray_image.shape
        
        # Ensure image is large enough
        if h < 16 or w < 16:
            return 0.0
        
        # Calculate horizontal differences at block boundaries (every 8 pixels)
        horizontal_diff = 0
        count_h = 0
        for y in range(8, h - 8, 8):
            diff = np.abs(gray_image[y, :].astype(float) - gray_image[y - 1, :].astype(float))
            horizontal_diff += np.mean(diff)
            count_h += 1
        
        # Calculate vertical differences at block boundaries
        vertical_diff = 0
        count_v = 0
        for x in range(8, w - 8, 8):
            diff = np.abs(gray_image[:, x].astype(float) - gray_image[:, x - 1].astype(float))
            vertical_diff += np.mean(diff)
            count_v += 1
        
        # Average blockiness
        if count_h > 0 and count_v > 0:
            blockiness = (horizontal_diff / count_h + vertical_diff / count_v) / 2
            return blockiness
        
        return 0.0
