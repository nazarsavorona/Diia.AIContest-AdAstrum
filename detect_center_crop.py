"""
Script to process photos:
- Face detection
- Crop to 2:3 aspect ratio (width:height)
- Center the face so it occupies ~60% of the frame
"""

import cv2
import os
from pathlib import Path
from PIL import Image
import numpy as np


def detect_face(image_path):
    """Detect a face in the photo."""
    # Load Haar cascade for face detection
    face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')

    # Read image
    img = cv2.imread(str(image_path))
    if img is None:
        print(f"Error: failed to load {image_path}")
        return None, None
    
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Detect faces
    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5, minSize=(30, 30))

    if len(faces) == 0:
        print(f"No face detected in {image_path}")
        return img, None

    # Take the first detected face (typically the largest)
    x, y, w, h = faces[0]
    
    return img, (x, y, w, h)


def crop_photo_for_document(image, face_rect, aspect_ratio=(2, 3)):
    """
    Crop a photo to a 2:3 aspect ratio with the face centered and occupying ~60% of the frame.

    Args:
        image: input image in BGR format
        face_rect: face coordinates (x, y, w, h) or None
        aspect_ratio: target aspect ratio (width, height)

    Returns:
        cropped image
    """
    height, width = image.shape[:2]
    
    if face_rect is None:
        # If no face is detected, crop around the image center
        center_x, center_y = width // 2, height // 2
        face_w, face_h = width // 3, height // 3
    else:
        x, y, w, h = face_rect
        center_x = x + w // 2
        center_y = y + h // 2
        face_w, face_h = w, h
    
    # The face should occupy ~60% of the frame height
    # For a 2:3 ratio the height is larger than the width
    target_face_ratio = 0.6
    
    # Calculate the required crop height so the face occupies ~60% of the frame
    crop_height = int(face_h / target_face_ratio)
    
    # Calculate width based on 2:3 aspect ratio
    crop_width = int(crop_height * aspect_ratio[0] / aspect_ratio[1])
    
    # Ensure dimensions do not exceed the original image
    if crop_width > width or crop_height > height:
        # Scale down while maintaining aspect ratio
        if crop_width > width:
            scale = width / crop_width
            crop_width = width
            crop_height = int(crop_height * scale)
        if crop_height > height:
            scale = height / crop_height
            crop_height = height
            crop_width = int(crop_width * scale)
    
    # Calculate crop coordinates (center the face)
    # Move the face slightly above center (as is common for document photos)
    offset_y = int(crop_height * 0.05)  # shift face up by 5% of crop height
    
    left = center_x - crop_width // 2
    top = center_y - crop_height // 2 - offset_y
    
    # Adjust if the crop goes outside the image bounds
    if left < 0:
        left = 0
    if top < 0:
        top = 0
    if left + crop_width > width:
        left = width - crop_width
    if top + crop_height > height:
        top = height - crop_height
    
    # Perform the crop
    cropped = image[top:top+crop_height, left:left+crop_width]
    
    return cropped


def process_directory(input_dir, output_dir, target_size=(600, 900)):
    """
    Process all photos in a directory, preserving folder hierarchy.

    Args:
        input_dir: input directory with photos
        output_dir: output directory for saving processed images
        target_size: target size (width, height) for the final image
    """
    input_path = Path(input_dir)
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Find all JPG files
    image_files = list(input_path.glob("*.jpg")) + list(input_path.glob("*.JPG"))

    if not image_files:
        return 0  # No images found

    print(f"\nProcessing folder: {input_path.name}")
    print(f"Found {len(image_files)} photos")

    processed_count = 0
    for idx, image_file in enumerate(image_files, 1):
        # Detect face
        img, face_rect = detect_face(image_file)

        if img is None:
            continue

        # Crop the photo
        cropped = crop_photo_for_document(img, face_rect)

        # Resize to the target size
        cropped_pil = Image.fromarray(cv2.cvtColor(cropped, cv2.COLOR_BGR2RGB))
        resized = cropped_pil.resize(target_size, Image.Resampling.LANCZOS)

        # Save with preserved hierarchy
        output_file = output_path / image_file.name
        resized.save(output_file, quality=95)
        processed_count += 1
        print(f"  [{idx}/{len(image_files)}] ✓ {image_file.name}")

    return processed_count


def process_nested_directories(input_base_dir, output_base_dir, target_size=(600, 900), max_folders=None):
    """
    Process all photos in nested directories, preserving folder hierarchy.

    Args:
        input_base_dir: base input directory
        output_base_dir: base output directory
        target_size: target size (width, height) for the final image
        max_folders: maximum number of folders to process (None for all)
    """
    input_path = Path(input_base_dir)
    output_path = Path(output_base_dir)
    
    if not input_path.exists():
        print(f"Error: Input directory does not exist: {input_path}")
        return
    
    # Get all subdirectories
    subdirs = sorted([d for d in input_path.iterdir() if d.is_dir()])
    
    if max_folders is not None:
        subdirs = subdirs[:max_folders]
    
    total_processed = 0
    total_folders = len(subdirs)
    
    print(f"Processing {total_folders} folders from: {input_base_dir}")
    print(f"Output directory: {output_base_dir}\n")
    print("="*60)
    
    for folder_idx, subdir in enumerate(subdirs, 1):
        # Create corresponding output folder preserving hierarchy
        relative_path = subdir.relative_to(input_path)
        subdir_output = output_path / relative_path
        
        print(f"\n[Folder {folder_idx}/{total_folders}] {relative_path}")
        
        # Process images in this folder
        count = process_directory(subdir, subdir_output, target_size)
        total_processed += count
    
    # Print summary
    print("\n" + "="*60)
    print("PROCESSING SUMMARY")
    print("="*60)
    print(f"Total folders processed: {total_folders}")
    print(f"Total images processed: {total_processed}")
    print(f"Output saved to: {output_path}")
    print("="*60)


if __name__ == "__main__":
    # Paths
    input_directory = "fixtures/FLUXSynID/FLUXSynID"
    output_directory = "fixtures/FLUXSynID-processed"
    
    # Process nested directories with hierarchy preservation
    # Limit to 250 folders, use target size 600x900 (2:3 ratio)
    process_nested_directories(
        input_directory, 
        output_directory, 
        target_size=(600, 900),
        max_folders=250
    )
