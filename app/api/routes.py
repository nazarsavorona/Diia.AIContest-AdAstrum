"""
API routes for photo validation
"""

from fastapi import APIRouter, HTTPException, UploadFile, File
from fastapi.responses import JSONResponse
import logging

from app.api.models import (
    ValidationRequest,
    ValidationResponse,
    StreamValidationResponse,
    HealthResponse,
    ValidationMode
)
from app.core.pipeline import ValidationPipeline
from app import __version__
import config

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create router
router = APIRouter()

# Initialize pipelines (singleton pattern for model loading)
_full_pipeline = None
_stream_pipeline = None


def get_full_pipeline() -> ValidationPipeline:
    """Get or initialize full validation pipeline"""
    global _full_pipeline
    if _full_pipeline is None:
        logger.info("Initializing full validation pipeline...")
        _full_pipeline = ValidationPipeline(mode=config.MODE_FULL)
        logger.info("Full validation pipeline initialized")
    return _full_pipeline


def get_stream_pipeline() -> ValidationPipeline:
    """Get or initialize stream validation pipeline"""
    global _stream_pipeline
    if _stream_pipeline is None:
        logger.info("Initializing stream validation pipeline...")
        _stream_pipeline = ValidationPipeline(mode=config.MODE_STREAM)
        logger.info("Stream validation pipeline initialized")
    return _stream_pipeline


@router.get("/health", response_model=HealthResponse)
async def health_check():
    """
    Health check endpoint
    """
    try:
        # Check if models can be loaded
        pipeline = get_stream_pipeline()
        models_loaded = True
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        models_loaded = False
    
    return HealthResponse(
        status="healthy" if models_loaded else "degraded",
        version=__version__,
        models_loaded=models_loaded
    )


@router.post("/validate/photo", response_model=ValidationResponse)
async def validate_photo(request: ValidationRequest):
    """
    Validate a photo with complete analysis
    
    This endpoint runs the full validation pipeline including all checks:
    - Format and resolution
    - Lighting and quality
    - Face detection and landmarks
    - Head pose estimation
    - Face geometry (size, centering)
    - Background analysis (segmentation)
    
    Use this for final photo validation before submission.
    """
    try:
        # Select pipeline based on mode
        if request.mode == ValidationMode.FULL:
            pipeline = get_full_pipeline()
            result = pipeline.validate(request.image, is_base64=True)
        else:
            pipeline = get_stream_pipeline()
            result = pipeline.validate_stream(request.image, is_base64=True)
        
        return ValidationResponse(
            status=result['status'],
            errors=result['errors'],
            metadata=result.get('metadata')
        )
        
    except Exception as e:
        logger.error(f"Validation error: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error during validation: {str(e)}"
        )


@router.post("/validate/stream", response_model=StreamValidationResponse)
async def validate_stream(request: ValidationRequest):
    """
    Fast validation for real-time camera stream
    
    This endpoint runs a lightweight validation pipeline optimized for speed:
    - Format and resolution
    - Lighting and quality
    - Face detection and landmarks
    - Head pose estimation
    - Face geometry (size, centering)
    
    Skips heavy models (background segmentation) for faster response times.
    Returns face landmarks and guidance data for real-time UI overlay.
    
    Use this for live camera feedback to help users position themselves correctly.
    """
    try:
        pipeline = get_stream_pipeline()
        result = pipeline.validate_stream(request.image, is_base64=True)
        
        return StreamValidationResponse(
            status=result['status'],
            errors=result['errors'],
            landmarks=result.get('landmarks'),
            guidance=result.get('guidance')
        )
        
    except Exception as e:
        logger.error(f"Stream validation error: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error during stream validation: {str(e)}"
        )


@router.post("/validate/upload")
async def validate_upload(file: UploadFile = File(...)):
    """
    Validate photo from file upload
    
    Alternative endpoint that accepts file upload instead of base64.
    Runs full validation pipeline.
    """
    try:
        # Read file contents
        contents = await file.read()
        
        # Validate file size
        if len(contents) > config.MAX_IMAGE_SIZE:
            raise HTTPException(
                status_code=400,
                detail=f"File too large. Maximum size: {config.MAX_IMAGE_SIZE / (1024*1024):.1f}MB"
            )
        
        # Run validation
        pipeline = get_full_pipeline()
        result = pipeline.validate(contents, is_base64=False)
        
        return ValidationResponse(
            status=result['status'],
            errors=result['errors'],
            metadata=result.get('metadata')
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Upload validation error: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error during upload validation: {str(e)}"
        )


@router.post("/debug/base64")
async def debug_base64(request: dict):
    """
    Debug endpoint to diagnose base64 issues
    
    Send your base64 string here to get detailed diagnostic information.
    This helps identify encoding/format issues before validation.
    """
    try:
        import base64
        
        base64_string = request.get('image', '')
        
        # Basic info
        info = {
            'input_length': len(base64_string),
            'has_data_uri_prefix': ',' in base64_string[:100],
        }
        
        # Clean the string
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        
        base64_string = base64_string.strip().replace('\n', '').replace('\r', '')
        
        info['cleaned_length'] = len(base64_string)
        info['padding_needed'] = len(base64_string) % 4
        
        # Try to decode
        try:
            missing_padding = len(base64_string) % 4
            if missing_padding:
                base64_string += '=' * (4 - missing_padding)
            
            img_data = base64.b64decode(base64_string, validate=True)
            info['decoded_bytes'] = len(img_data)
            
            # Check file signature
            if len(img_data) >= 4:
                signature = img_data[:4].hex()
                info['file_signature'] = signature
                
                # Identify format
                if signature.startswith('ffd8ff'):
                    info['detected_format'] = 'JPEG'
                elif signature.startswith('89504e47'):
                    info['detected_format'] = 'PNG'
                else:
                    info['detected_format'] = 'Unknown'
            
            # Try to open as image
            from PIL import Image
            import io
            try:
                img = Image.open(io.BytesIO(img_data))
                img.load()
                info['pil_format'] = img.format
                info['pil_mode'] = img.mode
                info['pil_size'] = img.size
                info['status'] = 'Valid image - should work for validation'
            except Exception as e:
                info['pil_error'] = str(e)
                info['status'] = 'Invalid image format'
                
        except Exception as e:
            info['decode_error'] = str(e)
            info['status'] = 'Base64 decode failed'
        
        return info
        
    except Exception as e:
        return {
            'error': str(e),
            'status': 'Debug failed'
        }
