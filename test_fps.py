#!/usr/bin/env python3
"""
Quick FPS test script - tests API speed with minimal overhead
"""

import base64
import requests
import time
from pathlib import Path
import statistics

BASE_URL = "https://d28w3hxcjjqa9z.cloudfront.net/api/v1"
PROCESSED_DATA_DIR = "FLUXSynID-processed"
NUM_IMAGES = 20  # Number of images to test


def encode_image_to_base64(image_path: Path) -> str:
    """Read image and encode to base64"""
    with open(image_path, "rb") as img_file:
        return base64.b64encode(img_file.read()).decode('utf-8')


def main():
    print("="*60)
    print("Quick FPS Test")
    print("="*60)
    
    # Collect test images
    processed_dir = Path(PROCESSED_DATA_DIR)
    if not processed_dir.exists():
        print(f"Error: {PROCESSED_DATA_DIR} not found!")
        return
    
    print(f"\nCollecting {NUM_IMAGES} test images...")
    test_images = []
    for person_dir in processed_dir.iterdir():
        if person_dir.is_dir():
            for img_file in person_dir.glob("*.jpg"):
                test_images.append(img_file)
                if len(test_images) >= NUM_IMAGES:
                    break
        if len(test_images) >= NUM_IMAGES:
            break
    
    print(f"Found {len(test_images)} images to test\n")
    
    # Run tests
    request_times = []
    successful = 0
    failed = 0
    
    print("Testing API speed...")
    print("-" * 60)
    
    for i, img_path in enumerate(test_images, 1):
        try:
            # Encode image
            base64_image = encode_image_to_base64(img_path)
            
            # Send request
            start_time = time.time()
            response = requests.post(
                f"{BASE_URL}/validate/photo",
                json={"image": base64_image, "mode": "full"},
                timeout=30
            )
            request_time = time.time() - start_time
            
            if response.status_code == 200:
                successful += 1
                request_times.append(request_time)
                status = response.json().get("status", "unknown")
                print(f"  [{i}/{len(test_images)}] ✓ {img_path.name}: {request_time:.3f}s ({status})")
            else:
                failed += 1
                print(f"  [{i}/{len(test_images)}] ✗ {img_path.name}: Error {response.status_code}")
                
        except Exception as e:
            failed += 1
            print(f"  [{i}/{len(test_images)}] ✗ {img_path.name}: {e}")
    
    # Calculate statistics
    if request_times:
        avg_time = statistics.mean(request_times)
        min_time = min(request_times)
        max_time = max(request_times)
        median_time = statistics.median(request_times)
        fps = 1.0 / avg_time if avg_time > 0 else 0
        
        print("\n" + "="*60)
        print("RESULTS")
        print("="*60)
        print(f"\nRequests:")
        print(f"  Successful: {successful}")
        print(f"  Failed: {failed}")
        print(f"  Total: {len(test_images)}")
        
        print(f"\nTiming:")
        print(f"  Average: {avg_time:.3f}s")
        print(f"  Median:  {median_time:.3f}s")
        print(f"  Min:     {min_time:.3f}s")
        print(f"  Max:     {max_time:.3f}s")
        
        print(f"\nPerformance:")
        print(f"  FPS (based on average): {fps:.2f} images/second")
        print(f"  FPS (based on median):  {1.0/median_time:.2f} images/second")
        print(f"  Images per minute:      {fps * 60:.0f}")
        
        print("\n" + "="*60)
    else:
        print("\n✗ No successful requests to analyze")


if __name__ == "__main__":
    main()
