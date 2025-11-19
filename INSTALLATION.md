# Installation Guide

## System Requirements

- Python 3.10 or conda
- 4GB+ RAM (8GB+ recommended for background segmentation)
- GPU optional but recommended for production (speeds up DeepLabV3)

## Installation Steps

### 1. Create Virtual Environment

```bash
conda create -n adastrum python=3.10
conda activate adastrum 
```

### 2. Install Dependencies

If you have a custom pip configuration (CodeArtifact, etc.), you may need to temporarily use the default PyPI:

```bash
pip install --index-url https://pypi.org/simple/ -r requirements.txt
```

### 3. Verify Installation

```bash
python test_setup.py
```

This will check that all packages are installed correctly and test the pipeline initialization.

### 4. Run the Server

```bash
python main.py
```

The API will be available at `http://localhost:8000`

## Docker Installation (Alternative)

If you prefer Docker and want to avoid dependency issues:

```bash
# Build the image
docker build -t photo-validator .

# Run the container
docker run -p 8000:8000 photo-validator

# With GPU support
docker run --gpus all -p 8000:8000 photo-validator
```

## Troubleshooting

### MediaPipe Installation Issues

If MediaPipe fails to install, try:

```bash
pip install --upgrade pip
pip install mediapipe
```

### PyTorch Installation Issues

For CPU-only installation:

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cpu
```

For GPU (CUDA 11.8):

```bash
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu118
```

### OpenCV Issues

If you get OpenCV errors related to GUI libraries:

```bash
pip uninstall opencv-python
pip install opencv-python-headless
```

## Next Steps

After successful installation:

1. Test the API: Visit `http://localhost:8000/docs`
2. Try the health endpoint: `curl http://localhost:8000/api/v1/health`
3. Test with a sample image (see README.md)
4. Export landmarks from fixture images if needed:
   ```bash
   python3 export_landmarks.py -f fixtures/FLUXSynID --mode stream
   ```
   (Generates `.txt` files and annotated `_landmarks` images; add `--skip-overlay` to disable previews or `--connections mesh` for full tessellation lines.)
5. Adjust configuration thresholds in `config.py` as needed
