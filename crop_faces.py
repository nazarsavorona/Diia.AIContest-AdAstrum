"""
Script to detect and crop face regions from images in nested folders.
Processes all images in FLUXSynID folder and saves cropped faces to FLUXSynID-faces.
"""

import cv2
import os
from pathlib import Path
from PIL import Image
import numpy as np


def detect_face_region(image_path):
    """
    Detect face region in the image.
    
    Args:
        image_path: path to the image file
    
    Returns:
        tuple: (image, face_rect) where face_rect is (x, y, w, h) or None
    """
    # Load Haar cascade for face detection
    face_cascade = cv2.CascadeClassifier(
        cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
    )
    
    # Read image
    img = cv2.imread(str(image_path))
    if img is None:
        print(f"Error: failed to load {image_path}")
        return None, None
    
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Detect faces
    faces = face_cascade.detectMultiScale(
        gray, 
        scaleFactor=1.1, 
        minNeighbors=5, 
        minSize=(30, 30)
    )
    
    if len(faces) == 0:
        print(f"Warning: No face detected in {image_path}")
        return img, None
    
    # Take the first detected face (typically the largest)
    x, y, w, h = faces[0]
    
    return img, (x, y, w, h)


def crop_face_with_margin(image, face_rect, margin_ratio=0.3):
    """
    Crop the face region with additional margin around it.
    
    Args:
        image: input image in BGR format
        face_rect: face coordinates (x, y, w, h) or None
        margin_ratio: ratio of margin to add around the face (default 0.3 = 30%)
    
    Returns:
        cropped face image or None if no face detected
    """
    if face_rect is None:
        return None
    
    height, width = image.shape[:2]
    x, y, w, h = face_rect
    
    # Calculate margins
    margin_w = int(w * margin_ratio)
    margin_h = int(h * margin_ratio)
    
    # Calculate crop coordinates with margins
    left = max(0, x - margin_w)
    top = max(0, y - margin_h)
    right = min(width, x + w + margin_w)
    bottom = min(height, y + h + margin_h)
    
    # Crop the image
    cropped = image[top:bottom, left:right]
    
    return cropped


def process_nested_folders(input_base_dir, output_base_dir, margin_ratio=0.3, max_samples=None):
    """
    Process all images in nested identity folders.
    
    Args:
        input_base_dir: base directory containing identity folders
        output_base_dir: base directory for saving cropped faces
        margin_ratio: ratio of margin to add around detected faces
        max_samples: maximum number of images to process (None for no limit)
    """
    input_path = Path(input_base_dir)
    output_path = Path(output_base_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    if not input_path.exists():
        print(f"Error: Input directory does not exist: {input_path}")
        return
    
    # Statistics
    total_images = 0
    faces_detected = 0
    faces_not_detected = 0
    
    # Iterate through identity folders
    identity_folders = sorted([f for f in input_path.iterdir() if f.is_dir()])
    
    if not identity_folders:
        print(f"No identity folders found in {input_path}")
        return
    
    print(f"Found {len(identity_folders)} identity folders")
    print(f"Processing images from: {input_base_dir}")
    print(f"Saving cropped faces to: {output_base_dir}\n")
    
    for identity_folder in identity_folders:
        identity_name = identity_folder.name
        
        # Create corresponding output folder
        identity_output_path = output_path / identity_name
        identity_output_path.mkdir(parents=True, exist_ok=True)
        
        # Find all image files in the identity folder
        image_files = []
        for ext in ['*.jpg', '*.jpeg', '*.png', '*.JPG', '*.JPEG', '*.PNG']:
            image_files.extend(identity_folder.glob(ext))
        
        if not image_files:
            print(f"No images found in {identity_name}")
            continue
        
        print(f"\nProcessing identity: {identity_name} ({len(image_files)} images)")
        
        for image_file in image_files:
            # Check if we've reached the maximum number of samples
            if max_samples is not None and total_images >= max_samples:
                print(f"\n⚠ Reached maximum sample limit ({max_samples}). Stopping.")
                break
            
            total_images += 1
            
            # Detect face
            img, face_rect = detect_face_region(image_file)
            
            if img is None:
                continue
            
            # Crop face with margin
            cropped_face = crop_face_with_margin(img, face_rect, margin_ratio)
            
            if cropped_face is not None:
                faces_detected += 1
                
                # Convert BGR to RGB for PIL
                cropped_face_rgb = cv2.cvtColor(cropped_face, cv2.COLOR_BGR2RGB)
                cropped_pil = Image.fromarray(cropped_face_rgb)
                
                # Save cropped face
                output_file = identity_output_path / image_file.name
                cropped_pil.save(output_file, quality=95)
                print(f"  ✓ Saved: {identity_name}/{image_file.name}")
            else:
                faces_not_detected += 1
                print(f"  ✗ Skipped (no face): {identity_name}/{image_file.name}")
        
        # Check if we've reached the limit after processing this identity folder
        if max_samples is not None and total_images >= max_samples:
            break
    
    # Print summary
    print("\n" + "="*60)
    print("PROCESSING SUMMARY")
    print("="*60)
    print(f"Total images processed: {total_images}")
    print(f"Faces detected and cropped: {faces_detected}")
    print(f"Images without face detection: {faces_not_detected}")
    print(f"Success rate: {faces_detected/total_images*100:.1f}%")
    print(f"\nCropped faces saved to: {output_path}")
    print("="*60)


if __name__ == "__main__":
    # Configuration
    input_directory = "fixtures/FLUXSynID-processed"
    output_directory = "fixtures/FLUXSynID-faces"
    margin_ratio = 0.01  # 1% margin around detected face
    max_samples = 1000  # Maximum number of images to process (set to None for no limit)
    
    # Run processing
    process_nested_folders(input_directory, output_directory, margin_ratio, max_samples)
