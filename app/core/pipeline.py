"""
Validation pipeline that orchestrates all validators
"""

from typing import Dict, Any, List
import numpy as np
import io

from app.validators.step1_format import FormatValidator
from app.validators.step2_quality import QualityValidator
from app.validators.step3_face import FaceDetectionValidator
from app.validators.step4_pose import PoseEstimationValidator
from app.validators.step5_geometry import GeometryValidator
from app.validators.step6_background import BackgroundValidator
from app.validators.step7_accessories import AccessoriesValidator
from app.core.errors import ValidationResult
from app.utils.image_utils import decode_base64_image, load_image_from_bytes
from app.utils.frame_debugger import stream_debugger
import config


class ValidationPipeline:
    """
    Orchestrates the complete photo validation pipeline
    """
    
    def __init__(self, mode: str = config.MODE_FULL):
        """
        Initialize the validation pipeline
        
        Args:
            mode: Validation mode ('full' or 'stream')
        """
        self.mode = mode
        
        # Initialize validators based on mode
        self.validators = self._initialize_validators()
    
    def _initialize_validators(self) -> List:
        """Initialize validators based on mode"""
        validators = []
        
        # Step 1: Format validation (always run)
        validators.append(('format', FormatValidator()))
        
        # Step 2: Quality checks (always run)
        validators.append(('quality', QualityValidator()))
        
        # Step 3: Face detection (always run)
        validators.append(('face', FaceDetectionValidator()))
        
        # Step 4: Pose estimation (always run)
        validators.append(('pose', PoseEstimationValidator()))
        
        # Step 5: Geometry checks (always run)
        validators.append(('geometry', GeometryValidator()))
        
        # Step 6: Background analysis (only in full mode, heavy model)
        if self.mode == config.MODE_FULL:
            validators.append(('background', BackgroundValidator()))
        
        # Step 7: Accessories detection (optional, disabled by default)
        # validators.append(('accessories', AccessoriesValidator(enabled=False)))
        
        return validators
    
    def validate(self, image_data: Any, is_base64: bool = True) -> Dict[str, Any]:
        """
        Run the complete validation pipeline
        
        Args:
            image_data: Image as base64 string or bytes
            is_base64: Whether image_data is base64 encoded
            
        Returns:
            Dictionary with validation results
        """
        # Decode image
        try:
            if is_base64:
                image = decode_base64_image(image_data)
                # For format validation, we need the raw bytes
                if "," in image_data:
                    image_data_clean = image_data.split(",")[1]
                else:
                    image_data_clean = image_data
                import base64
                image_bytes = base64.b64decode(image_data_clean)
            else:
                image = load_image_from_bytes(image_data)
                image_bytes = image_data
        except Exception as e:
            return {
                'status': 'fail',
                'errors': [{
                    'code': 'invalid_image',
                    'message': f'Failed to decode image: {str(e)}'
                }],
                'metadata': {}
            }
        
        # Initialize context for sharing data between validators
        context = {
            'image_bytes': image_bytes
        }
        
        # Run validators sequentially
        all_errors = []
        all_metadata = {}
        
        for name, validator in self.validators:
            try:
                result = validator.validate(image, context)
                
                # Collect errors
                if not result.passed:
                    all_errors.extend([error.to_dict() for error in result.errors])
                
                # Merge metadata
                all_metadata[name] = result.metadata
                
                # Update context with results for next validators
                context.update(result.metadata)
                
                # Early exit on critical failures
                if name == 'format' and not result.passed:
                    # If format is invalid, no point continuing
                    break
                
                if name == 'face' and not result.passed:
                    # If no face detected, can't continue with pose/geometry
                    break
                
            except Exception as e:
                # Log error but continue
                all_metadata[name] = {
                    'error': str(e),
                    'validator_failed': True
                }
        
        # Determine overall status
        status = 'success' if len(all_errors) == 0 else 'fail'
        
        return {
            'status': status,
            'errors': all_errors,
            'metadata': all_metadata
        }
    
    def validate_stream(self, image_data: Any, is_base64: bool = True) -> Dict[str, Any]:
        """
        Run fast validation for real-time streaming (skips heavy models)
        
        This is optimized for low latency and runs only essential checks
        
        Args:
            image_data: Image as base64 string or bytes
            is_base64: Whether image_data is base64 encoded
            
        Returns:
            Dictionary with validation results and landmarks for UI guidance
        """
        # Decode image
        try:
            if is_base64:
                image = decode_base64_image(image_data)
                if "," in image_data:
                    image_data_clean = image_data.split(",")[1]
                else:
                    image_data_clean = image_data
                import base64
                image_bytes = base64.b64decode(image_data_clean)
            else:
                image = load_image_from_bytes(image_data)
                image_bytes = image_data
        except Exception as e:
            return {
                'status': 'fail',
                'errors': [{
                    'code': 'invalid_image',
                    'message': f'Failed to decode image: {str(e)}'
                }],
                'landmarks': None,
                'guidance': {}
            }
        
        # Initialize context
        context = {
            'image_bytes': image_bytes
        }
        
        # Run lightweight validators only (steps 1-5)
        lightweight_validators = [v for v in self.validators if v[0] not in ['background', 'accessories']]
        
        all_errors = []
        landmarks = None
        guidance = {}
        
        for name, validator in lightweight_validators:
            try:
                result = validator.validate(image, context)
                
                if not result.passed:
                    all_errors.extend([error.to_dict() for error in result.errors])
                
                # Extract landmarks for UI
                if name == 'face' and 'landmarks' in result.metadata:
                    landmarks = result.metadata.get('landmarks')
                    guidance['face_bbox'] = result.metadata.get('face_bbox')
                
                # Extract pose for UI
                if name == 'pose':
                    guidance['pose'] = {
                        'yaw': result.metadata.get('yaw'),
                        'pitch': result.metadata.get('pitch'),
                        'roll': result.metadata.get('roll')
                    }
                
                # Extract geometry for UI
                if name == 'geometry':
                    guidance['centering'] = {
                        'offset_x': result.metadata.get('center_offset_x'),
                        'offset_y': result.metadata.get('center_offset_y')
                    }
                    guidance['face_size_ratio'] = result.metadata.get('face_size_ratio')
                
                context.update(result.metadata)
                
                # Early exit on critical failures
                if name == 'format' and not result.passed:
                    break
                if name == 'face' and not result.passed:
                    break
                
            except Exception as e:
                pass
        
        status = 'success' if len(all_errors) == 0 else 'fail'

        # Optionally show incoming stream frame in a debug window
        stream_debugger.show(image, status=status, errors=all_errors)
        
        return {
            'status': status,
            'errors': all_errors,
            'landmarks': landmarks,
            'guidance': guidance
        }
