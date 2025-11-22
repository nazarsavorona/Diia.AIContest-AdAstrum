"""
Lightweight frame saver for debugging validation requests.

Enabled via DEBUG_SAVE_FRAMES env var. Frames are saved to disk with annotations
showing validation status and errors.
"""

from __future__ import annotations

import logging
import os
from datetime import datetime
from pathlib import Path
from typing import Iterable, Optional

import cv2
import numpy as np

from app.core import settings


class FrameSaver:
    """Saves incoming validation frames to disk for debugging purposes."""

    def __init__(
        self,
        enabled: bool,
        output_dir: str,
        max_frames: int = 100,
    ):
        """
        Initialize the frame saver.

        Args:
            enabled: Whether frame saving is enabled
            output_dir: Directory path where frames will be saved
            max_frames: Maximum number of frames to keep (oldest will be deleted)
        """
        self.enabled = enabled
        self.output_dir = Path(output_dir)
        self.max_frames = max_frames
        self._logger = logging.getLogger(__name__)
        self._frame_count = 0

        if self.enabled:
            self._ensure_output_dir()
            self._logger.info("Frame saver enabled; output_dir=%s", self.output_dir)
        else:
            self._logger.debug("Frame saver disabled.")

    def _ensure_output_dir(self) -> None:
        """Create output directory if it doesn't exist."""
        try:
            self.output_dir.mkdir(parents=True, exist_ok=True)
        except Exception as exc:
            self._logger.error("Failed to create output directory %s: %s", self.output_dir, exc)
            self.enabled = False

    def save(
        self,
        frame: np.ndarray,
        *,
        status: Optional[str] = None,
        errors: Optional[Iterable] = None,
    ) -> None:
        """
        Save a frame to disk with annotations.

        Args:
            frame: Image frame as numpy array (BGR format)
            status: Validation status ('success' or 'fail')
            errors: List of validation errors
        """
        if not self.enabled or frame is None:
            return

        try:
            # Annotate the frame
            annotated = self._annotate_frame(frame, status=status, errors=errors)

            # Generate filename with timestamp and status
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            status_str = status or "unknown"
            filename = f"frame_{timestamp}_{status_str}.jpg"
            filepath = self.output_dir / filename

            # Save the frame
            cv2.imwrite(str(filepath), annotated)
            self._frame_count += 1
            self._logger.debug("Saved frame: %s", filename)

            # Clean up old frames if we exceed max_frames
            self._cleanup_old_frames()

        except Exception as exc:
            self._logger.warning("Failed to save frame: %s", exc)

    def _cleanup_old_frames(self) -> None:
        """Remove oldest frames if we exceed max_frames limit."""
        try:
            # Get all frame files sorted by modification time
            frame_files = sorted(
                self.output_dir.glob("frame_*.jpg"),
                key=lambda p: p.stat().st_mtime
            )

            # Delete oldest files if we exceed the limit
            while len(frame_files) > self.max_frames:
                oldest_file = frame_files.pop(0)
                oldest_file.unlink()
                self._logger.debug("Deleted old frame: %s", oldest_file.name)

        except Exception as exc:
            self._logger.warning("Failed to cleanup old frames: %s", exc)

    def _annotate_frame(
        self,
        frame: np.ndarray,
        *,
        status: Optional[str] = None,
        errors: Optional[Iterable] = None,
    ) -> np.ndarray:
        """
        Overlay validation info on the frame.

        Args:
            frame: Original frame
            status: Validation status
            errors: List of validation errors

        Returns:
            Annotated frame with text overlays
        """
        annotated = frame.copy()

        text_lines = []
        if status:
            text_lines.append(f"status: {status}")

        error_codes = []
        if errors:
            for err in errors:
                if isinstance(err, dict):
                    code = err.get("code") or err.get("message")
                else:
                    code = str(err)
                if code:
                    error_codes.append(code)
        if error_codes:
            text_lines.append(f"errors: {', '.join(error_codes[:2])}")

        # Add timestamp
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        text_lines.append(f"time: {timestamp}")

        if text_lines:
            color = (0, 200, 0) if status == "success" else (0, 0, 255)
            for idx, line in enumerate(text_lines):
                y = 30 + idx * 24
                cv2.putText(
                    annotated,
                    line,
                    (10, y),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    color,
                    2,
                    cv2.LINE_AA,
                )

        return annotated

    def clear_all_frames(self) -> int:
        """
        Delete all saved frames from the output directory.

        Returns:
            Number of frames deleted
        """
        try:
            frame_files = list(self.output_dir.glob("frame_*.jpg"))
            count = len(frame_files)
            for frame_file in frame_files:
                frame_file.unlink()
            self._logger.info("Deleted %d frames from %s", count, self.output_dir)
            return count
        except Exception as exc:
            self._logger.error("Failed to clear frames: %s", exc)
            return 0


# Initialize the global frame saver instance
frame_saver = FrameSaver(
    enabled=settings.DEBUG_SAVE_FRAMES,
    output_dir=settings.DEBUG_FRAMES_DIR,
    max_frames=settings.DEBUG_MAX_FRAMES,
)

__all__ = ["frame_saver", "FrameSaver"]
