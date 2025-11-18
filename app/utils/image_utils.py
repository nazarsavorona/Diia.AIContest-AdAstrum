"""
Image processing utilities
"""

import base64
import io
from typing import Tuple, Optional
import numpy as np
from PIL import Image
import cv2


def decode_base64_image(base64_string: str) -> np.ndarray:
    """
    Decode base64 string to numpy array (BGR format for OpenCV)
    
    Args:
        base64_string: Base64 encoded image string
        
    Returns:
        numpy array in BGR format
        
    Raises:
        ValueError: If the image cannot be decoded
    """
    try:
        # Remove data URI prefix if present
        if "," in base64_string:
            base64_string = base64_string.split(",")[1]
        
        # Remove any whitespace and newlines
        base64_string = base64_string.strip().replace('\n', '').replace('\r', '').replace(' ', '').replace('\t', '')
        
        # Handle URL-encoded base64 (replace URL-safe characters)
        base64_string = base64_string.replace('-', '+').replace('_', '/')
        
        # Remove any non-base64 characters (keep only A-Z, a-z, 0-9, +, /, =)
        import re
        base64_string = re.sub(r'[^A-Za-z0-9+/=]', '', base64_string)
        
        # Validate base64 string is not empty
        if not base64_string:
            raise ValueError("Base64 string is empty after cleaning")
        
        # Fix padding if necessary
        # Base64 strings should be divisible by 4
        missing_padding = len(base64_string) % 4
        if missing_padding:
            base64_string += '=' * (4 - missing_padding)
        
        # Decode base64
        try:
            img_data = base64.b64decode(base64_string, validate=True)
        except Exception as e:
            # Try one more time without validation
            try:
                img_data = base64.b64decode(base64_string, validate=False)
            except Exception as e2:
                raise ValueError(f"Invalid base64 encoding: {str(e)}. Even non-strict decoding failed: {str(e2)}")
        
        # Check if we have actual data
        if len(img_data) == 0:
            raise ValueError("Decoded image data is empty")
        
        # Check if we have actual data
        if len(img_data) < 10:
            raise ValueError(f"Image data too short to be a valid image ({len(img_data)} bytes)")
        
        # Check file signature
        signature = img_data[:4].hex()
        first_bytes = img_data[:20].hex()
        
        # Identify common formats
        format_info = "Unknown"
        if signature.startswith('ffd8ff'):
            format_info = "JPEG"
        elif signature.startswith('89504e47'):
            format_info = "PNG"
        elif signature.startswith('474946'):
            format_info = "GIF (not supported)"
        elif signature.startswith('424d'):
            format_info = "BMP (not supported)"
        elif signature.startswith('52494646') and img_data[8:12].hex() == '57454250':
            format_info = "WebP (not supported)"
        else:
            format_info = f"Unknown (signature: {signature}, first 20 bytes: {first_bytes})"
        
        # Try to identify format with PIL
        img_bytes = io.BytesIO(img_data)
        
        # Convert to PIL Image
        try:
            pil_image = Image.open(img_bytes)
            pil_image.load()  # Force load to validate image
        except Exception as e:
            raise ValueError(
                f"Cannot identify image format. "
                f"Detected format: {format_info}. "
                f"PIL error: {str(e)}. "
                f"Only JPEG and PNG are supported. "
                f"Data length: {len(img_data)} bytes. "
                f"Hint: Make sure you're sending the actual image file data encoded in base64, "
                f"not a file path or other data."
            )
        
        # Convert to RGB if necessary
        if pil_image.mode != 'RGB':
            pil_image = pil_image.convert('RGB')
        
        # Convert to numpy array (RGB)
        img_array = np.array(pil_image)
        
        # Convert RGB to BGR for OpenCV
        img_bgr = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
        
        return img_bgr
        
    except ValueError:
        raise
    except Exception as e:
        raise ValueError(f"Failed to decode image: {str(e)}")


def load_image_from_bytes(image_bytes: bytes) -> np.ndarray:
    """
    Load image from bytes
    
    Args:
        image_bytes: Image as bytes
        
    Returns:
        numpy array in BGR format
    """
    pil_image = Image.open(io.BytesIO(image_bytes))
    
    if pil_image.mode != 'RGB':
        pil_image = pil_image.convert('RGB')
    
    img_array = np.array(pil_image)
    img_bgr = cv2.cvtColor(img_array, cv2.COLOR_RGB2BGR)
    
    return img_bgr


def get_image_format(image_bytes: bytes) -> Optional[str]:
    """
    Get image format from bytes
    
    Args:
        image_bytes: Image as bytes
        
    Returns:
        Format string (e.g., 'JPEG', 'PNG') or None
    """
    try:
        pil_image = Image.open(io.BytesIO(image_bytes))
        return pil_image.format
    except Exception:
        return None


def get_image_dimensions(image: np.ndarray) -> Tuple[int, int]:
    """
    Get image dimensions
    
    Args:
        image: numpy array
        
    Returns:
        Tuple of (height, width)
    """
    return image.shape[:2]


def calculate_aspect_ratio(width: int, height: int) -> float:
    """
    Calculate aspect ratio as max/min dimension
    
    Args:
        width: Image width
        height: Image height
        
    Returns:
        Aspect ratio as float
    """
    return max(width, height) / min(width, height)


def resize_image(image: np.ndarray, max_dimension: int = 1920) -> np.ndarray:
    """
    Resize image if it's too large, maintaining aspect ratio
    
    Args:
        image: Input image
        max_dimension: Maximum dimension
        
    Returns:
        Resized image
    """
    h, w = image.shape[:2]
    
    if max(h, w) <= max_dimension:
        return image
    
    if h > w:
        new_h = max_dimension
        new_w = int(w * (max_dimension / h))
    else:
        new_w = max_dimension
        new_h = int(h * (max_dimension / w))
    
    return cv2.resize(image, (new_w, new_h), interpolation=cv2.INTER_AREA)


def convert_bgr_to_rgb(image: np.ndarray) -> np.ndarray:
    """Convert BGR image to RGB"""
    return cv2.cvtColor(image, cv2.COLOR_BGR2RGB)


def convert_rgb_to_bgr(image: np.ndarray) -> np.ndarray:
    """Convert RGB image to BGR"""
    return cv2.cvtColor(image, cv2.COLOR_RGB2BGR)


def crop_face_region(image: np.ndarray, bbox: Tuple[int, int, int, int], margin: float = 0.2) -> np.ndarray:
    """
    Crop face region with margin
    
    Args:
        image: Input image
        bbox: Bounding box as (x, y, width, height)
        margin: Margin to add around face (as fraction of bbox size)
        
    Returns:
        Cropped face region
    """
    h, w = image.shape[:2]
    x, y, bw, bh = bbox
    
    # Add margin
    margin_w = int(bw * margin)
    margin_h = int(bh * margin)
    
    x1 = max(0, x - margin_w)
    y1 = max(0, y - margin_h)
    x2 = min(w, x + bw + margin_w)
    y2 = min(h, y + bh + margin_h)
    
    return image[y1:y2, x1:x2]


def encode_image_to_base64(image: np.ndarray, format: str = 'JPEG') -> str:
    """
    Encode numpy array to base64 string
    
    Args:
        image: Image as numpy array (BGR)
        format: Output format ('JPEG' or 'PNG')
        
    Returns:
        Base64 encoded string
    """
    # Convert BGR to RGB
    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    
    # Convert to PIL Image
    pil_image = Image.fromarray(image_rgb)
    
    # Encode to bytes
    buffer = io.BytesIO()
    pil_image.save(buffer, format=format)
    
    # Encode to base64
    img_str = base64.b64encode(buffer.getvalue()).decode()
    
    return img_str
