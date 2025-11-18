"""
Generate under-exposed images from FLUXSynID-faces dataset.
"""

import cv2
import numpy as np
from pathlib import Path


def create_underexposed_image(image, intensity=0.4):
    """
    Create an under-exposed version by decreasing brightness.
    
    Args:
        image: input BGR image
        intensity: darkness multiplier (< 1.0)
    
    Returns:
        under-exposed image
    """
    dark = cv2.convertScaleAbs(image, alpha=intensity, beta=-30)
    return dark


def generate_underexposed_images(input_dir, output_dir, max_samples=500):
    """
    Generate under-exposed variations from input images.
    
    Args:
        input_dir: input directory with face images
        output_dir: output directory for under-exposed images
        max_samples: maximum number of samples to generate
    """
    input_path = Path(input_dir)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    if not input_path.exists():
        print(f"Error: Input directory does not exist: {input_path}")
        return
    
    count = 0
    identity_folders = sorted([f for f in input_path.iterdir() if f.is_dir()])
    
    print(f"Generating under-exposed images from: {input_dir}")
    print(f"Output directory: {output_dir}")
    print(f"Max samples: {max_samples}\n")
    
    for identity_folder in identity_folders:
        identity_name = identity_folder.name
        
        # Find all image files
        image_files = []
        for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
            image_files.extend(identity_folder.glob(ext))
        
        for image_file in image_files:
            if count >= max_samples:
                print(f"\n✓ Reached maximum limit ({max_samples}). Stopping.")
                break
            
            # Load image
            img = cv2.imread(str(image_file))
            if img is None:
                continue
            
            # Create identity subfolder
            identity_output_dir = output_path / identity_name
            identity_output_dir.mkdir(parents=True, exist_ok=True)
            
            # Apply under-exposure
            underexposed_img = create_underexposed_image(img, intensity=0.35)
            
            # Save
            output_file = identity_output_dir / image_file.name
            cv2.imwrite(str(output_file), underexposed_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            count += 1
            if count % 50 == 0:
                print(f"Generated {count} images...")
        
        if count >= max_samples:
            break
    
    print(f"\n{'='*60}")
    print(f"✓ Generated {count} under-exposed images")
    print(f"Output: {output_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    input_directory = "fixtures/FLUXSynID-faces"
    output_directory = "fixtures/FLUXSynID-under-exposed"
    max_samples = 500
    
    generate_underexposed_images(input_directory, output_directory, max_samples)
