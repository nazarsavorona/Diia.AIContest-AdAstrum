"""
Generate images with uneven lighting/shadows from FLUXSynID-faces dataset.
"""

import cv2
import numpy as np
from pathlib import Path
import random


def create_uneven_lighting_image(image, shadow_intensity=0.6):
    """
    Create uneven lighting by applying a gradient shadow on one side.
    
    Args:
        image: input BGR image
        shadow_intensity: darkness of shadow (< 1.0)
    
    Returns:
        image with uneven lighting
    """
    h, w = image.shape[:2]
    
    # Create a gradient mask (left to right or top to bottom)
    if random.random() > 0.5:
        # Vertical gradient (left darker)
        gradient = np.linspace(shadow_intensity, 1.0, w)
        mask = np.tile(gradient, (h, 1))
    else:
        # Horizontal gradient (top darker)
        gradient = np.linspace(shadow_intensity, 1.0, h)
        mask = np.tile(gradient.reshape(-1, 1), (1, w))
    
    # Apply mask to all channels
    mask_3d = np.stack([mask] * 3, axis=2)
    shadowed = (image.astype(np.float32) * mask_3d).astype(np.uint8)
    
    return shadowed


def generate_uneven_lighting_images(input_dir, output_dir, max_samples=500):
    """
    Generate uneven lighting variations from input images.
    
    Args:
        input_dir: input directory with face images
        output_dir: output directory for shadowed images
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
    
    print(f"Generating uneven lighting images from: {input_dir}")
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
            
            # Apply uneven lighting
            shadowed_img = create_uneven_lighting_image(img, shadow_intensity=0.5)
            
            # Save
            output_file = identity_output_dir / image_file.name
            cv2.imwrite(str(output_file), shadowed_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            count += 1
            if count % 50 == 0:
                print(f"Generated {count} images...")
        
        if count >= max_samples:
            break
    
    print(f"\n{'='*60}")
    print(f"✓ Generated {count} uneven lighting images")
    print(f"Output: {output_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    input_directory = "fixtures/FLUXSynID-faces"
    output_directory = "fixtures/FLUXSynID-uneven-lighting"
    max_samples = 500
    
    generate_uneven_lighting_images(input_directory, output_directory, max_samples)
