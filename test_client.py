"""
Test client for Photo Validation API
"""

import base64
import requests
import json
from pathlib import Path


def test_with_sample_image(image_path: str, mode: str = "full"):
    """
    Test the API with a sample image
    
    Args:
        image_path: Path to image file
        mode: "full" or "stream"
    """
    print(f"\nTesting with image: {image_path}")
    print(f"Mode: {mode}")
    print("-" * 60)
    
    # Read and encode image
    try:
        with open(image_path, 'rb') as f:
            img_data = base64.b64encode(f.read()).decode('utf-8')
        print(f"✓ Image loaded and encoded (size: {len(img_data)} chars)")
    except Exception as e:
        print(f"✗ Failed to load image: {e}")
        return
    
    # Prepare request
    url = "http://localhost:8000/api/v1/validate/photo"
    payload = {
        "image": img_data,
        "mode": mode
    }
    
    # Send request
    try:
        print(f"Sending request to {url}...")
        response = requests.post(url, json=payload, timeout=30)
        
        print(f"Response status: {response.status_code}")
        print("-" * 60)
        
        # Parse and display response
        result = response.json()
        print(json.dumps(result, indent=2))
        
        # Summary
        print("\n" + "=" * 60)
        if result.get('status') == 'success':
            print("✓ VALIDATION PASSED")
        else:
            print("✗ VALIDATION FAILED")
            if result.get('errors'):
                print(f"\nErrors found ({len(result['errors'])}):")
                for error in result['errors']:
                    print(f"  - [{error['code']}] {error['message']}")
        print("=" * 60)
        
    except requests.exceptions.RequestException as e:
        print(f"✗ Request failed: {e}")
        print("\nMake sure the server is running:")
        print("  python main.py")


def test_health_check():
    """Test the health check endpoint"""
    print("\nTesting health check endpoint...")
    print("-" * 60)
    
    try:
        response = requests.get("http://localhost:8000/api/v1/health", timeout=5)
        print(f"Response status: {response.status_code}")
        result = response.json()
        print(json.dumps(result, indent=2))
        
        if result.get('status') == 'healthy':
            print("\n✓ API is healthy and ready")
        else:
            print("\n⚠ API health check returned degraded status")
            
    except requests.exceptions.RequestException as e:
        print(f"✗ Health check failed: {e}")
        print("\nMake sure the server is running:")
        print("  python main.py")


def test_base64_debug(base64_string: str):
    """
    Test the base64 debug endpoint to diagnose encoding issues
    """
    print("\nTesting base64 encoding...")
    print("-" * 60)
    
    try:
        response = requests.post(
            "http://localhost:8000/api/v1/debug/base64",
            json={'image': base64_string},
            timeout=5
        )
        
        result = response.json()
        print(json.dumps(result, indent=2))
        
        if result.get('status') == 'Valid image - should work for validation':
            print("\n✓ Base64 encoding is valid")
            return True
        else:
            print(f"\n✗ Base64 issue detected: {result.get('status')}")
            return False
            
    except Exception as e:
        print(f"✗ Debug check failed: {e}")
        return False


def create_test_image():
    """
    Create a simple test image for demonstration
    This creates a basic image that will fail validation (by design)
    to demonstrate the API functionality
    """
    try:
        from PIL import Image, ImageDraw
        import numpy as np
        
        # Create a simple 600x900 image (2:3 ratio)
        img = Image.new('RGB', (600, 900), color='white')
        draw = ImageDraw.Draw(img)
        
        # Draw a simple "face" (circle with dots for eyes)
        draw.ellipse([200, 300, 400, 500], fill='beige', outline='black')
        draw.ellipse([250, 350, 280, 380], fill='black')  # Left eye
        draw.ellipse([320, 350, 350, 380], fill='black')  # Right eye
        draw.arc([270, 420, 330, 450], 0, 180, fill='black')  # Smile
        
        # Save
        img.save('test_image.jpg')
        print("✓ Created test_image.jpg (simple test image)")
        return 'test_image.jpg'
        
    except Exception as e:
        print(f"✗ Failed to create test image: {e}")
        return None


if __name__ == "__main__":
    print("=" * 60)
    print("Photo Validation API - Test Client")
    print("=" * 60)
    
    # Test health check first
    test_health_check()
    
    # Check if we have a test image
    test_image_path = None
    
    # Try to find a sample image
    for ext in ['.jpg', '.jpeg', '.png']:
        for name in ['test_photo', 'sample', 'test_image', 'photo']:
            path = Path(f"{name}{ext}")
            if path.exists():
                test_image_path = str(path)
                break
        if test_image_path:
            break
    
    # If no image found, create a simple one
    if not test_image_path:
        print("\nNo test image found. Creating a simple test image...")
        test_image_path = create_test_image()
    
    # Test with the image
    if test_image_path:
        print("\n" + "=" * 60)
        print("Testing Full Validation")
        print("=" * 60)
        test_with_sample_image(test_image_path, mode="full")
        
        print("\n" + "=" * 60)
        print("Testing Stream Validation")
        print("=" * 60)
        test_with_sample_image(test_image_path, mode="stream")
    else:
        print("\n⚠ No test image available")
        print("\nTo test with your own image:")
        print("  python test_client.py")
        print("\nOr place a photo named 'test_photo.jpg' in this directory")
