"""
Configuration and threshold values for photo validation
"""

# Image format requirements
ALLOWED_FORMATS = ["JPEG", "PNG"]
TARGET_ASPECT_RATIO = 1.25  # center around square-to-35x45 passports
ASPECT_RATIO_TOLERANCE = 0.35  # allow synthetic square crops and mild deviations
MIN_RESOLUTION = 600  # minimum dimension in pixels
MIN_RESOLUTION_OPTIMAL = 1200  # recommended minimum

# JPEG quality thresholds
MIN_JPEG_QUALITY = 85  # approximate quality level
JPEG_BLOCKINESS_THRESHOLD = 15.0  # variance threshold for blocking artifacts

# Lighting and quality thresholds
BLUR_THRESHOLD = 100.0  # Laplacian variance threshold
MIN_CONTRAST = 30.0  # minimum standard deviation of luminance
MAX_CONTRAST = 80.0  # maximum standard deviation
BRIGHTNESS_LOW_THRESHOLD = 50  # histogram analysis
BRIGHTNESS_HIGH_THRESHOLD = 220
OVEREXPOSED_PIXEL_RATIO = 0.7  # fraction of pixels allowed above high threshold
SHADOW_DIFFERENCE_THRESHOLD = 60  # brightness difference for shadow detection

# Face detection thresholds
MIN_FACE_DETECTION_CONFIDENCE = 0.7
EXPECTED_FACE_COUNT = 1

# Head pose thresholds (degrees)
MAX_YAW = 15.0  # left/right turn
MAX_PITCH = 10.0  # up/down tilt
MAX_ROLL = 20.0  # head tilt

# Face geometry thresholds
MIN_FACE_AREA_RATIO = 0.15  # allow smaller crops in synthetic passports
MAX_FACE_AREA_RATIO = 0.7  # 70% of image
FACE_CENTER_TOLERANCE = 0.15  # ±15% of image dimensions
HAIR_OCCLUSION_THRESHOLD = 0.3  # edge density around jawline

# Background thresholds
BACKGROUND_UNIFORMITY_THRESHOLD = 10.0  # color variance threshold
MIN_BACKGROUND_RATIO = 0.3  # minimum background portion
MIN_PERSON_SEGMENT_AREA = 15000  # minimum pixels to count an extra person
EXTRA_PERSON_MIN_RATIO = 0.1  # extra person pixels vs full frame to trigger error

# MediaPipe configuration
MEDIAPIPE_MAX_NUM_FACES = 2  # detect up to 2 faces to check for extras
MEDIAPIPE_MIN_DETECTION_CONFIDENCE = 0.7
MEDIAPIPE_MIN_TRACKING_CONFIDENCE = 0.5

# Model paths (will be downloaded automatically)
DEEPLAB_MODEL = "deeplabv3_mobilenet_v3_large"

# API configuration
MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB max upload
ALLOWED_EXTENSIONS = {".jpg", ".jpeg", ".png"}

# Processing modes
MODE_FULL = "full"  # Complete validation
MODE_STREAM = "stream"  # Fast validation for real-time (skips heavy models)
