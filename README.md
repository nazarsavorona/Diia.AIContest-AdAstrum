# Photo Validation API

API for validating ID/passport photos for the Diia app. This service performs comprehensive validation of photos including format checks, quality assessment, face detection, pose estimation, and background analysis.

## Features

- **Format Validation**: Aspect ratio (2:3), resolution, and file format checks
- **Quality Assessment**: Lighting, exposure, blur, and shadow detection
- **Face Detection**: MediaPipe-based face detection with landmark extraction
- **Pose Estimation**: Head pose analysis using PnP algorithm
- **Geometry Checks**: Face size, centering, and occlusion detection
- **Background Analysis**: DeepLabV3-based segmentation for uniform background verification
- **Real-time Streaming**: Fast validation mode for live camera feedback

## Quick Start

### Prerequisites

- Python 3.10+
- Docker (optional, for containerized deployment)

### Local Development

1. **Install dependencies**:
```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

2. **Run the server**:
```bash
python main.py
```

The API will be available at `http://localhost:8000`

3. **Access API documentation**:
- Swagger UI: `http://localhost:8000/docs`
- ReDoc: `http://localhost:8000/redoc`

### Docker Deployment

1. **Build the Docker image**:
```bash
docker build -t photo-validator .
```

2. **Run the container**:
```bash
docker run -p 8000:8000 photo-validator
```

For GPU support (recommended for production):
```bash
docker run --gpus all -p 8000:8000 photo-validator
```

## API Endpoints

### Health Check
```http
GET /api/v1/health
```

Returns service health status and model availability.

### Full Photo Validation
```http
POST /api/v1/validate/photo
Content-Type: application/json

{
  "image": "base64_encoded_image_data",
  "mode": "full"
}
```

Runs complete validation pipeline including background segmentation.

**Response**:
```json
{
  "status": "success" | "fail",
  "errors": [
    {
      "code": "error_code",
      "message": "Human-readable error message"
    }
  ],
  "metadata": {
    "format": {...},
    "quality": {...},
    "face": {...},
    "pose": {...},
    "geometry": {...},
    "background": {...}
  }
}
```

### Stream Validation (Real-time)
```http
POST /api/v1/validate/stream
Content-Type: application/json

{
  "image": "base64_encoded_image_data",
  "mode": "stream"
}
```

Fast validation optimized for real-time camera feedback. Skips heavy models.

**Response**:
```json
{
  "status": "success" | "fail",
  "errors": [...],
  "landmarks": [...],
  "guidance": {
    "face_bbox": [x, y, width, height],
    "pose": {"yaw": 0.0, "pitch": 0.0, "roll": 0.0},
    "centering": {"offset_x": 0.05, "offset_y": 0.03},
    "face_size_ratio": 0.6
  }
}
```

### Upload Validation
```http
POST /api/v1/validate/upload
Content-Type: multipart/form-data

file: <image_file>
```

Alternative endpoint accepting file uploads instead of base64.

## Configuration

Edit `config.py` to adjust validation thresholds:

```python
# Aspect ratio
TARGET_ASPECT_RATIO = 1.5  # 2:3
ASPECT_RATIO_TOLERANCE = 0.05  # ±5%

# Resolution
MIN_RESOLUTION = 600  # pixels

# Quality thresholds
BLUR_THRESHOLD = 100.0
MIN_CONTRAST = 30.0

# Pose thresholds
MAX_YAW = 15.0  # degrees
MAX_PITCH = 10.0
MAX_ROLL = 10.0

# Geometry
MIN_FACE_AREA_RATIO = 0.5  # 50% of image
MAX_FACE_AREA_RATIO = 0.7  # 70% of image
FACE_CENTER_TOLERANCE = 0.15  # ±15%
```

## Error Codes

| Code | Description |
|------|-------------|
| `wrong_aspect_ratio` | Image aspect ratio not 2:3 |
| `resolution_too_low` | Image resolution below minimum |
| `unsupported_file_format` | Only JPEG/PNG supported |
| `low_quality_or_too_compressed` | JPEG compression too high |
| `insufficient_lighting` | Image too dark |
| `overexposed_or_too_bright` | Image too bright |
| `strong_shadows_on_face` | Harsh shadows detected |
| `image_blurry_or_out_of_focus` | Image not sharp |
| `no_face_detected` | No face found |
| `more_than_one_person_in_photo` | Multiple faces detected |
| `head_is_tilted` | Head tilt exceeds threshold |
| `face_not_looking_straight_at_camera` | Face not forward-facing |
| `face_too_small_in_frame` | Face occupies <50% of frame |
| `face_too_close_or_cropped` | Face occupies >70% of frame |
| `face_not_centered` | Face not centered in frame |
| `hair_covers_part_of_face` | Hair occludes face contour |
| `background_not_uniform` | Background not plain/uniform |
| `extraneous_people_in_background` | Additional people present |
| `extraneous_objects_in_background` | Objects in background |

## Architecture

```
photo-validator/
├── app/
│   ├── api/              # FastAPI routes and models
│   ├── core/             # Pipeline orchestration
│   ├── utils/            # Image processing utilities
│   └── validators/       # Step-by-step validators
│       ├── step1_format.py      # Format & resolution
│       ├── step2_quality.py     # Lighting & blur
│       ├── step3_face.py        # Face detection (MediaPipe)
│       ├── step4_pose.py        # Pose estimation (PnP)
│       ├── step5_geometry.py    # Geometry checks
│       ├── step6_background.py  # Segmentation (DeepLabV3)
│       └── step7_accessories.py # VLM (optional)
├── config.py            # Configuration & thresholds
├── main.py             # FastAPI application
├── requirements.txt    # Python dependencies
└── Dockerfile         # Container configuration
```

## Models Used

- **MediaPipe Face Detection**: Lightweight face detection
- **MediaPipe Face Mesh**: 468 facial landmarks
- **DeepLabV3-MobileNetV3**: Semantic segmentation for background analysis
- **OpenCV solvePnP**: Head pose estimation

## Performance

- **Stream mode**: ~200-500ms per image (CPU)
- **Full mode**: ~1-2s per image (CPU), ~500ms with GPU
- Models are loaded once at startup for optimal performance

## iOS Integration

For integration with the Diia iOS app:

1. Configure CORS in `main.py` to allow your iOS app domain
2. Use `/validate/stream` endpoint for real-time camera feedback
3. Use `/validate/photo` with `mode: "full"` for final submission
4. Implement UI overlays using returned `landmarks` and `guidance` data

Example iOS request:
```swift
let base64Image = imageData.base64EncodedString()
let request = [
    "image": "data:image/jpeg;base64,\(base64Image)",
    "mode": "stream"
]
```

## Deployment on vast.ai

1. **Create instance** with GPU (e.g., RTX 3090)
2. **Upload code** or clone from GitHub
3. **Build and run**:
```bash
docker build -t photo-validator .
docker run -d --gpus all -p 8000:8000 photo-validator
```

4. **Configure firewall** to expose port 8000
5. **Use public IP** in iOS app: `http://<vast-instance-ip>:8000`

## Testing

### Quick Test

Run the included test client:

```bash
python test_client.py
```

This will:
1. Check API health
2. Create a test image (if none exists)
3. Test both full and stream validation modes
4. Display detailed results

### Manual Test

Test with your own image:

```bash
python -c "
import base64
import requests

# Read and encode image
with open('your_photo.jpg', 'rb') as f:
    img_data = base64.b64encode(f.read()).decode('utf-8')

# Send validation request
response = requests.post(
    'http://localhost:8000/api/v1/validate/photo',
    json={'image': img_data, 'mode': 'full'}
)

print(response.json())
"
```

### Exporting Landmarks from Local Fixtures

Use the `export_landmarks.py` helper to run the validation pipeline on local images (or entire fixture folders) and store the detected landmarks as `.txt` files:

```bash
# Single image
python3 export_landmarks.py -i path/to/photo.jpg --mode stream

# Whole fixture directory, keeping the folder structure in landmark_exports/
python3 export_landmarks.py -f fixtures/FLUXSynID-over-exposed --include-3d -o landmark_exports
```

Key options:
- `--mode` selects `full` (all checks) or `stream` (fast, default) pipeline.
- `--include-3d` adds the 3D mesh coordinates when available.
- `--output-dir` chooses where the `.txt` exports are written (default `landmark_exports/`).
- Pass `-i` multiple times for individual photos or `-f` for directories (recursively scanned).
- Annotated preview images with the detected points are produced automatically (file name suffix `_landmarks`). Skip them with `--skip-overlay` if you only need the `.txt`.
- Use `--connections mesh|contours|none` to control whether the preview also connects landmarks with full tessellation lines, contour-only outlines (default), or only dots.

Each export file lists the validation status, any errors, and all landmark coordinates, and the companion annotated image makes it easy to visually confirm the detection without going through the API.

### Common Issues

**Base64 Padding Error**: The API automatically fixes base64 padding issues. If you're sending from iOS/JavaScript, you can send the base64 string with or without padding - the server will handle it.

**Image Format**: Only JPEG and PNG are supported. Make sure your base64 string is properly encoded.

## License

MIT

## Contact

For questions or issues, please open a GitHub issue or contact the development team.
