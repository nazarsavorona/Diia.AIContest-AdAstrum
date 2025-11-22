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

# Frame saver settings for debugging - saves frames to disk instead of displaying
DEBUG_SAVE_FRAMES = os.getenv("DEBUG_SAVE_FRAMES", "true").lower() == "true"
DEBUG_FRAMES_DIR = os.getenv("DEBUG_FRAMES_DIR", "debug_frames")
DEBUG_MAX_FRAMES = int(os.getenv("DEBUG_MAX_FRAMES", "100"))

__all__ = [
    "APP_NAME",
    "LOG_LEVEL",
    "AWS_REGION",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_SESSION_TOKEN",
    "MODEL_WARMUP",
    "TORCH_DEVICE",
    "DEBUG_SAVE_FRAMES",
    "DEBUG_FRAMES_DIR",
    "DEBUG_MAX_FRAMES",
]
