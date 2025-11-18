"""
Step 6: Background and extraneous object detection using segmentation
"""

from typing import Dict, Any
import numpy as np
import cv2
import torch
import torchvision.models.segmentation as segmentation
from torchvision import transforms

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
import config


class BackgroundValidator(BaseValidator):
    """Validates background uniformity and detects extraneous objects"""
    
    def __init__(self):
        super().__init__()
        
        # Load DeepLabV3 with MobileNetV3 backbone
        self.model = segmentation.deeplabv3_mobilenet_v3_large(pretrained=True)
        self.model.eval()
        
        # Move to GPU if available
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.model = self.model.to(self.device)
        
        # Preprocessing transforms
        self.preprocess = transforms.Compose([
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225]
            )
        ])
        
        # COCO class index for person
        self.PERSON_CLASS = 15
    
    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Validate background uniformity and detect extraneous objects
        
        Args:
            image: Input image as numpy array (BGR format)
            context: Optional context
            
        Returns:
            ValidationResult
        """
        result = self._create_result()
        
        # Perform segmentation
        segmentation_mask = self._segment_image(image)
        
        if segmentation_mask is None:
            # If segmentation fails, don't fail validation completely
            result.metadata = {
                'segmentation_available': False
            }
            return result
        
        # Check for multiple people
        person_count = self._count_persons(segmentation_mask)
        if person_count > 1:
            result.add_error(
                ErrorCode.EXTRANEOUS_PEOPLE,
                f"Detected {person_count} people in the image"
            )
        
        # Check background uniformity
        background_variance = self._check_background_uniformity(
            image, segmentation_mask, result
        )
        
        # Check for extraneous objects in background
        object_score = self._check_extraneous_objects(
            segmentation_mask, result
        )
        
        # Store segmentation data in metadata
        result.metadata = {
            'segmentation_available': True,
            'person_count': int(person_count),
            'background_variance': float(background_variance),
            'extraneous_object_score': float(object_score)
        }
        
        return result
    
    def _segment_image(self, image: np.ndarray) -> np.ndarray:
        """
        Perform semantic segmentation on the image
        
        Returns:
            Segmentation mask (HxW array with class indices)
        """
        try:
            # Convert BGR to RGB
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            
            # Preprocess
            input_tensor = self.preprocess(image_rgb)
            input_batch = input_tensor.unsqueeze(0).to(self.device)
            
            # Perform inference
            with torch.no_grad():
                output = self.model(input_batch)['out'][0]
            
            # Get class predictions
            output_predictions = output.argmax(0).cpu().numpy()
            
            return output_predictions
            
        except Exception as e:
            return None
    
    def _count_persons(self, segmentation_mask: np.ndarray) -> int:
        """
        Count number of distinct person regions in segmentation mask
        
        Returns:
            Number of persons detected
        """
        # Create binary mask for person class
        person_mask = (segmentation_mask == self.PERSON_CLASS).astype(np.uint8)
        
        # Find connected components
        num_labels, labels = cv2.connectedComponents(person_mask)
        
        # Subtract 1 for background label
        # Also filter out very small regions (noise)
        person_count = 0
        min_area = 1000  # minimum pixels for a valid person region
        
        for label in range(1, num_labels):
            area = np.sum(labels == label)
            if area > min_area:
                person_count += 1
        
        return person_count
    
    def _check_background_uniformity(self, image: np.ndarray, segmentation_mask: np.ndarray, result: ValidationResult) -> float:
        """
        Check if background is uniform by analyzing color variance
        
        Returns:
            Background variance score
        """
        try:
            # Create background mask (exclude person)
            background_mask = (segmentation_mask != self.PERSON_CLASS).astype(np.uint8)
            
            # Get background pixels
            background_pixels = image[background_mask == 1]
            
            if len(background_pixels) < 100:
                # Not enough background pixels
                return 0.0
            
            # Convert to LAB color space for better color uniformity assessment
            background_bgr = background_pixels.reshape(-1, 1, 3)
            background_lab = cv2.cvtColor(background_bgr, cv2.COLOR_BGR2LAB)
            background_lab = background_lab.reshape(-1, 3)
            
            # Calculate standard deviation for each channel
            std_l = np.std(background_lab[:, 0])
            std_a = np.std(background_lab[:, 1])
            std_b = np.std(background_lab[:, 2])
            
            # Average variance
            variance = (std_l + std_a + std_b) / 3
            
            if variance > config.BACKGROUND_UNIFORMITY_THRESHOLD:
                result.add_error(
                    ErrorCode.BACKGROUND_NOT_UNIFORM,
                    f"Background is not uniform (variance: {variance:.1f})"
                )
            
            return variance
            
        except Exception as e:
            return 0.0
    
    def _check_extraneous_objects(self, segmentation_mask: np.ndarray, result: ValidationResult) -> float:
        """
        Check for extraneous objects in the background
        
        This looks for non-person, non-background objects in the segmentation
        
        Returns:
            Score indicating presence of extraneous objects
        """
        try:
            # Get unique classes excluding background (0) and person (15)
            unique_classes = np.unique(segmentation_mask)
            
            # Classes to exclude: 0 (background), 15 (person)
            # Also exclude common background classes that are acceptable
            acceptable_classes = {0, 15}  # background and person
            
            extraneous_classes = [c for c in unique_classes if c not in acceptable_classes]
            
            if not extraneous_classes:
                return 0.0
            
            # Calculate total area of extraneous objects
            total_pixels = segmentation_mask.size
            extraneous_pixels = 0
            
            for cls in extraneous_classes:
                extraneous_pixels += np.sum(segmentation_mask == cls)
            
            extraneous_ratio = extraneous_pixels / total_pixels
            
            # If extraneous objects occupy more than 5% of image, flag it
            if extraneous_ratio > 0.05:
                result.add_error(
                    ErrorCode.EXTRANEOUS_OBJECTS,
                    f"Extraneous objects detected in background ({extraneous_ratio * 100:.1f}% of image)"
                )
            
            return extraneous_ratio
            
        except Exception as e:
            return 0.0
    
    def __del__(self):
        """Clean up resources"""
        if hasattr(self, 'model'):
            del self.model
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
