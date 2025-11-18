"""
Generate low-contrast images from FLUXSynID-faces dataset.
"""

import cv2
import numpy as np
from pathlib import Path
from PIL import Image, ImageEnhance


def create_low_contrast_image(image, contrast_factor=0.5):
    """
    Create a low-contrast version.
    
    Args:
        image: input BGR image
        contrast_factor: contrast multiplier (< 1.0 for low contrast)
    
    Returns:
        low-contrast image
    """
    # Convert to PIL for easier contrast adjustment
    pil_img = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    enhancer = ImageEnhance.Contrast(pil_img)
    low_contrast = enhancer.enhance(contrast_factor)
    return cv2.cvtColor(np.array(low_contrast), cv2.COLOR_RGB2BGR)


def generate_low_contrast_images(input_dir, output_dir, max_samples=500):
    """
    Generate low-contrast variations from input images.
    
    Args:
        input_dir: input directory with face images
        output_dir: output directory for low-contrast images
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
    
    print(f"Generating low-contrast images from: {input_dir}")
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
            
            # Apply low contrast
            low_contrast_img = create_low_contrast_image(img, contrast_factor=0.4)
            
            # Save
            output_file = identity_output_dir / image_file.name
            cv2.imwrite(str(output_file), low_contrast_img, [cv2.IMWRITE_JPEG_QUALITY, 95])
            
            count += 1
            if count % 50 == 0:
                print(f"Generated {count} images...")
        
        if count >= max_samples:
            break
    
    print(f"\n{'='*60}")
    print(f"✓ Generated {count} low-contrast images")
    print(f"Output: {output_path}")
    print(f"{'='*60}")


if __name__ == "__main__":
    input_directory = "fixtures/FLUXSynID-faces"
    output_directory = "fixtures/FLUXSynID-low-contrast"
    max_samples = 500
    
    generate_low_contrast_images(input_directory, output_directory, max_samples)
