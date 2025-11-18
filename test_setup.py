"""
Quick test script to verify the setup and basic functionality
"""

import sys
import os

def test_imports():
    """Test that all required imports work"""
    print("Testing imports...")
    try:
        import fastapi
        print("✓ FastAPI installed")
        
        import cv2
        print("✓ OpenCV installed")
        
        import mediapipe
        print("✓ MediaPipe installed")
        
        import torch
        import torchvision
        print("✓ PyTorch and TorchVision installed")
        
        import numpy
        print("✓ NumPy installed")
        
        import PIL
        print("✓ Pillow installed")
        
        print("\nAll required packages are installed! ✓")
        return True
        
    except ImportError as e:
        print(f"\n✗ Import error: {e}")
        print("Please run: pip install -r requirements.txt")
        return False


def test_modules():
    """Test that application modules can be imported"""
    print("\nTesting application modules...")
    try:
        from app.core.errors import ValidationResult, ErrorCode
        print("✓ Core modules")
        
        from app.validators.base import BaseValidator
        print("✓ Base validator")
        
        from app.validators.step1_format import FormatValidator
        print("✓ Format validator")
        
        from app.validators.step2_quality import QualityValidator
        print("✓ Quality validator")
        
        from app.validators.step3_face import FaceDetectionValidator
        print("✓ Face detection validator")
        
        from app.validators.step4_pose import PoseEstimationValidator
        print("✓ Pose estimation validator")
        
        from app.validators.step5_geometry import GeometryValidator
        print("✓ Geometry validator")
        
        from app.validators.step6_background import BackgroundValidator
        print("✓ Background validator")
        
        from app.core.pipeline import ValidationPipeline
        print("✓ Validation pipeline")
        
        from app.api.routes import router
        print("✓ API routes")
        
        print("\nAll application modules loaded successfully! ✓")
        return True
        
    except Exception as e:
        print(f"\n✗ Module error: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_pipeline_initialization():
    """Test that the validation pipeline can be initialized"""
    print("\nTesting pipeline initialization...")
    try:
        from app.core.pipeline import ValidationPipeline
        import config
        
        # Try to initialize stream pipeline (lighter)
        pipeline = ValidationPipeline(mode=config.MODE_STREAM)
        print("✓ Stream pipeline initialized")
        
        # Try to initialize full pipeline
        pipeline_full = ValidationPipeline(mode=config.MODE_FULL)
        print("✓ Full pipeline initialized (this may take a moment to load models)")
        
        print("\nPipeline initialization successful! ✓")
        return True
        
    except Exception as e:
        print(f"\n✗ Pipeline initialization error: {e}")
        import traceback
        traceback.print_exc()
        return False


def main():
    """Run all tests"""
    print("=" * 60)
    print("Photo Validation API - Setup Test")
    print("=" * 60)
    
    results = []
    
    # Test imports
    results.append(("Imports", test_imports()))
    
    # Test modules
    results.append(("Modules", test_modules()))
    
    # Test pipeline initialization
    results.append(("Pipeline", test_pipeline_initialization()))
    
    # Summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)
    
    all_passed = True
    for name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{name:20} {status}")
        if not passed:
            all_passed = False
    
    print("=" * 60)
    
    if all_passed:
        print("\n✓ All tests passed! The system is ready to use.")
        print("\nNext steps:")
        print("1. Run the server: python main.py")
        print("2. Access API docs: http://localhost:8000/docs")
        print("3. Test with a sample image")
        return 0
    else:
        print("\n✗ Some tests failed. Please check the errors above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
