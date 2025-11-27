"""Simple settings loader using python-dotenv.
Loads environment variables from .env for local development.
In AWS ECS, environment variables should be injected via task definition or IAM roles.
"""
from __future__ import annotations
import os
from dotenv import load_dotenv

# Load .env if present
load_dotenv()

APP_NAME = os.getenv("APP_NAME", "Photo Validation API")
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO")
AWS_REGION = os.getenv("AWS_REGION")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY")
AWS_SESSION_TOKEN = os.getenv("AWS_SESSION_TOKEN")

# Optional runtime flags
MODEL_WARMUP = os.getenv("MODEL_WARMUP", "true").lower() == "true"
TORCH_DEVICE = os.getenv("TORCH_DEVICE", "cuda")
IMAGE_ENCRYPTION_KEY = os.getenv("IMAGE_ENCRYPTION_KEY", "diia-stream-shared-secret")
# Pin MiniCPM-o revision to avoid unexpected remote code changes
MINICPM_REVISION = os.getenv(
    "MINICPM_REVISION",
    "509805e84db1c84f154034d71a21c4f2331e6e11",
)

__all__ = [
    "APP_NAME",
    "LOG_LEVEL",
    "AWS_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "MODEL_WARMUP",
    "TORCH_DEVICE",
    "IMAGE_ENCRYPTION_KEY",
    "MINICPM_REVISION",
]
