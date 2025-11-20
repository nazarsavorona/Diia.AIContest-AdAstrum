import base64
import requests
import json
import io
from PIL import Image, ImageDraw

# Configuration
BASE_URL = "https://d28w3hxcjjqa9z.cloudfront.net/api/v1"

def create_dummy_image():
    """Create a simple valid image for testing"""
    # Create a 600x900 image (2:3 aspect ratio)
    img = Image.new('RGB', (600, 900), color='white')
    
    # Draw a simple face-like structure to maybe pass some checks (or at least be a valid image)
    draw = ImageDraw.Draw(img)
    # Face oval
    draw.ellipse((150, 200, 450, 600), fill='beige', outline='black')
    # Eyes
    draw.ellipse((200, 350, 250, 380), fill='white', outline='black')
    draw.ellipse((350, 350, 400, 380), fill='white', outline='black')
    # Pupils
    draw.ellipse((220, 360, 230, 370), fill='black')
    draw.ellipse((370, 360, 380, 370), fill='black')
    # Mouth
    draw.arc((250, 450, 350, 500), 0, 180, fill='black')
    
    # Save to bytes
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format='JPEG', quality=90)
    return img_byte_arr.getvalue()

def send_validation_request(base64_image, endpoint_suffix, mode=None):
    url = f"{BASE_URL}/{endpoint_suffix}"
    print(f"\nTesting endpoint: {url}")
    print("-" * 30)
    
    payload = {
        "image": base64_image
    }
    if mode:
        payload["mode"] = mode
    
    print("Sending request...")
    try:
        response = requests.post(url, json=payload, timeout=30)
        print(f"Response Status: {response.status_code}")
        
        if response.status_code == 200:
            try:
                result = response.json()
                print("\nAPI Response:")
                print(json.dumps(result, indent=2))
                
                status = result.get('status')
                if status:
                    print(f"\n✓ API Test Successful (Status: {status})")
                else:
                    print("\n? API response format unexpected")
            except json.JSONDecodeError:
                print("\nResponse is not standard JSON:")
                print(response.text[:500] + "...")
        else:
            print(f"\n✗ API Request Failed: {response.text}")
            
    except Exception as e:
        print(f"\n✗ Connection Error: {e}")

def test_health_check():
    url = f"{BASE_URL}/health"
    print(f"\nTesting endpoint: {url}")
    print("-" * 30)
    
    print("Sending request...")
    try:
        response = requests.get(url, timeout=10)
        print(f"Response Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print("\nAPI Response:")
            print(json.dumps(result, indent=2))
            
            version = result.get('version')
            if version == "1.0.2":
                print(f"\n✓ Health Check Successful (Version: {version})")
            else:
                print(f"\n? Health Check Warning: Expected version 1.0.2, got {version}")
        else:
            print(f"\n✗ Health Check Failed: {response.text}")
    except Exception as e:
        print(f"\n✗ Connection Error: {e}")

def test_api():
    print(f"Testing API Base URL: {BASE_URL}")
    
    # 0. Test Health Check
    test_health_check()
    
    # 1. Create test image
    print("Generating test image...")
    try:
        image_bytes = create_dummy_image()
        base64_image = base64.b64encode(image_bytes).decode('utf-8')
        print(f"✓ Image generated ({len(base64_image)} chars)")
    except Exception as e:
        print(f"✗ Failed to generate image: {e}")
        return

    # 2. Test /validate/photo (Full Mode)
    send_validation_request(base64_image, "validate/photo", mode="full")

    # 3. Test /validate/stream (Stream Endpoint)
    send_validation_request(base64_image, "validate/stream")

if __name__ == "__main__":
    test_api()
