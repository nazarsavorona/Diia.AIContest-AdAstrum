#!/usr/bin/env python3
"""
Simple script to test image validation with a local file
"""

import base64
import requests
import sys

def validate_image_file(image_path: str, mode: str = "full"):
    """
    Validate an image file
    
    Args:
        image_path: Path to the image file
        mode: "full" or "stream"
    """
    print(f"Reading image from: {image_path}")
    
    # Method 1: Base64 encoding
    print("\n" + "="*60)
    print("Method 1: Base64 Validation")
    print("="*60)
    
    try:
        # Read the file as binary
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
            print(f"✓ Read {len(image_bytes)} bytes from file")
        
        # Encode to base64
        base64_string = base64.b64encode(image_bytes).decode('utf-8')
        print(f"✓ Encoded to base64 ({len(base64_string)} characters)")
        
        # First, test with debug endpoint
        print("\nTesting base64 encoding...")
        debug_response = requests.post(
            'http://0.0.0.0:8000/api/v1/debug/base64',
            json={'image': base64_string}
        )
        debug_result = debug_response.json()
        print(f"Debug result: {debug_result.get('status')}")
        
        if 'Valid' in debug_result.get('status', ''):
            print("✓ Base64 encoding is valid\n")
            
            # Now validate
            print("Running validation...")
            response = requests.post(
                'http://0.0.0.0:8000/api/v1/validate/photo',
                json={'image': base64_string, 'mode': mode},
                timeout=30
            )
            
            result = response.json()
            print("\nValidation Result:")
            print("-"*60)
            print(f"Status: {result['status']}")
            
            if result.get('errors'):
                print(f"\nErrors found ({len(result['errors'])}):")
                for error in result['errors']:
                    print(f"  - [{error['code']}] {error['message']}")
            else:
                print("✓ No errors - photo is valid!")
                
        else:
            print(f"✗ Base64 issue: {debug_result}")
            
    except FileNotFoundError:
        print(f"✗ Error: File not found: {image_path}")
    except Exception as e:
        print(f"✗ Error: {e}")
    
    # Method 2: File upload
    print("\n" + "="*60)
    print("Method 2: Direct File Upload")
    print("="*60)
    
    try:
        with open(image_path, 'rb') as f:
            response = requests.post(
                'http://0.0.0.0:8000/api/v1/validate/upload',
                files={'file': f},
                timeout=30
            )
            
            result = response.json()
            print(f"Status: {result['status']}")
            
            if result.get('errors'):
                print(f"\nErrors found ({len(result['errors'])}):")
                for error in result['errors']:
                    print(f"  - [{error['code']}] {error['message']}")
            else:
                print("✓ No errors - photo is valid!")
                
    except Exception as e:
        print(f"✗ Error: {e}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python test_image.py <path_to_image> [mode]")
        print("Example: python test_image.py /Users/ihor.olkhovatyi/Desktop/image1.png full")
        sys.exit(1)
    
    image_path = sys.argv[1]
    mode = sys.argv[2] if len(sys.argv) > 2 else "full"
    
    validate_image_file(image_path, mode)
