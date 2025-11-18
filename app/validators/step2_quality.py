"""
Step 2: Lighting, exposure, blur, and shadow detection
"""

from typing import Dict, Any
import numpy as np
import cv2

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
import config


class QualityValidator(BaseValidator):
    """Validates image quality: lighting, exposure, blur, shadows"""
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Validate image quality
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Optional context (can contain face_bbox for targeted checks)
            
        Returns:
            ValidationResult
        """
        result = self._create_result()
        
        # Convert to grayscale for analysis
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Check blur
        blur_score = self._check_blur(gray, result)
        
        # Check exposure and contrast
        brightness_score, contrast_score = self._check_exposure_contrast(gray, result)
        
        # Check for shadows (if face region is available)
        if context and 'face_bbox' in context:
            face_region = self._extract_face_region(image, context['face_bbox'])
            if face_region is not None:
                shadow_score = self._check_shadows(face_region, result)
            else:
                shadow_score = 0.0
        else:
            # General shadow check on full image
            shadow_score = self._check_shadows(image, result)
        
        # Add metadata
        result.metadata = {
            'blur_score': float(blur_score),
            'brightness_score': float(brightness_score),
            'contrast_score': float(contrast_score),
            'shadow_score': float(shadow_score)
        }
        
        return result
    
    def _check_blur(self, gray_image: np.ndarray, result: ValidationResult) -> float:
        """
        Check image sharpness using Laplacian variance
        Lower values indicate more blur
        """
        laplacian = cv2.Laplacian(gray_image, cv2.CV_64F)
        variance = laplacian.var()
        
        if variance < config.BLUR_THRESHOLD:
            result.add_error(
                ErrorCode.IMAGE_BLURRY,
                f"Image is blurry (sharpness score: {variance:.2f})"
            )
        
        return variance
    
    def _check_exposure_contrast(self, gray_image: np.ndarray, result: ValidationResult) -> tuple:
        """
        Check exposure and contrast using histogram analysis
        
        Returns:
            Tuple of (brightness_score, contrast_score)
        """
        # Calculate mean brightness
        mean_brightness = np.mean(gray_image)
        
        # Calculate contrast (standard deviation of luminance)
        contrast = np.std(gray_image)
        
        # Check for underexposure
        low_pixel_ratio = np.sum(gray_image < config.BRIGHTNESS_LOW_THRESHOLD) / gray_image.size
        if low_pixel_ratio > 0.5 or mean_brightness < 60:
            result.add_error(
                ErrorCode.INSUFFICIENT_LIGHTING,
                f"Image is underexposed (brightness: {mean_brightness:.1f})"
            )
        
        # Check for overexposure
        high_pixel_ratio = np.sum(gray_image > config.BRIGHTNESS_HIGH_THRESHOLD) / gray_image.size
        if high_pixel_ratio > 0.5 or mean_brightness > 200:
            result.add_error(
                ErrorCode.OVEREXPOSED,
                f"Image is overexposed (brightness: {mean_brightness:.1f})"
            )
        
        # Check contrast
        if contrast < config.MIN_CONTRAST:
            result.add_error(
                ErrorCode.LOW_CONTRAST,
                f"Image has very low contrast (contrast: {contrast:.1f})"
            )
        
        return mean_brightness, contrast
    
    def _check_shadows(self, image: np.ndarray, result: ValidationResult) -> float:
        """
        Check for harsh shadows by comparing brightness in different regions
        """
        # Convert to grayscale if needed
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        
        h, w = gray.shape
        
        # Split image into quadrants
        mid_h, mid_w = h // 2, w // 2
        
        top_left = gray[:mid_h, :mid_w]
        top_right = gray[:mid_h, mid_w:]
        bottom_left = gray[mid_h:, :mid_w]
        bottom_right = gray[mid_h:, mid_w:]
        
        # Calculate mean brightness for each quadrant
        means = [
            np.mean(top_left),
            np.mean(top_right),
            np.mean(bottom_left),
            np.mean(bottom_right)
        ]
        
        # Calculate maximum difference
        max_diff = max(means) - min(means)
        
        if max_diff > config.SHADOW_DIFFERENCE_THRESHOLD:
            result.add_error(
                ErrorCode.STRONG_SHADOWS,
                f"Strong shadows or uneven lighting detected (difference: {max_diff:.1f})"
            )
        
        return max_diff
    
    def _extract_face_region(self, image: np.ndarray, bbox: tuple) -> np.ndarray:
        """
        Extract face region from bounding box
        
        Args:
            image: Input image
            bbox: (x, y, width, height)
            
        Returns:
            Face region or None if invalid
        """
        try:
            x, y, w, h = bbox
            h_img, w_img = image.shape[:2]
            
            # Ensure coordinates are within bounds
            x = max(0, min(x, w_img))
            y = max(0, min(y, h_img))
            w = min(w, w_img - x)
            h = min(h, h_img - y)
            
            if w > 0 and h > 0:
                return image[y:y+h, x:x+w]
        except Exception:
            pass
        
        return None
