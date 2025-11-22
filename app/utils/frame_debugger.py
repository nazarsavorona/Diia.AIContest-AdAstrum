"""
Lightweight OpenCV frame viewer for debugging stream requests.

Enabled via STREAM_DEBUG_SHOW_FRAMES env var. Frames are pushed to a background
thread so API handlers are not blocked by cv2.imshow.
"""

from __future__ import annotations

import logging
import os
import queue
import threading
from typing import Iterable, Optional

import cv2
import numpy as np

from app.core import settings


class FrameDebugger:
    """Displays incoming frames in an OpenCV window for quick visual debug."""

    def __init__(
        self,
        enabled: bool,
        window_name: str = "Stream Debug",
        max_queue: int = 3,
    ):
        self.enabled = enabled and self._display_available()
        self.window_name = window_name
        self.max_queue = max_queue

        self._queue: queue.Queue[np.ndarray] = queue.Queue(maxsize=max_queue)
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._logger = logging.getLogger(__name__)
        self._failed = False

        if self.enabled:
            self._logger.info("Frame debugger enabled; window=%s", self.window_name)
        else:
            self._logger.debug("Frame debugger disabled (flag off or no display).")

    def _display_available(self) -> bool:
        """Check if a display is available for cv2.imshow."""
        if os.name == "nt":
            return True
        return bool(os.environ.get("DISPLAY"))

    def start(self) -> None:
        """Start background display thread."""
        if not self.enabled or self._thread:
            return

        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def show(
        self,
        frame: np.ndarray,
        *,
        status: Optional[str] = None,
        errors: Optional[Iterable] = None,
    ) -> None:
        """
        Queue a frame for display. Drops oldest frame if the queue is full.
        """
        if not self.enabled or self._failed or frame is None:
            return

        if self._thread is None:
            self.start()

        annotated = self._annotate_frame(frame, status=status, errors=errors)

        try:
            self._queue.put_nowait(annotated)
        except queue.Full:
            try:
                self._queue.get_nowait()
                self._queue.put_nowait(annotated)
            except Exception:
                # If we cannot queue, just drop the frame silently
                pass
        except Exception as exc:  # pragma: no cover - defensive
            self._logger.warning("Failed to queue frame for debug display: %s", exc)
            self._failed = True

    def stop(self) -> None:
        """Stop the background display thread."""
        if not self._thread:
            return

        self._stop_event.set()
        self._thread.join(timeout=1.0)
        self._thread = None

    # Internal helpers
    def _run(self) -> None:
        try:
            cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
        except Exception as exc:
            self._logger.warning("Disabling frame debugger (window error): %s", exc)
            self._failed = True
            return

        while not self._stop_event.is_set():
            try:
                frame = self._queue.get(timeout=0.1)
            except queue.Empty:
                continue

            try:
                cv2.imshow(self.window_name, frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    self._stop_event.set()
                    break
            except Exception as exc:
                self._logger.warning("Disabling frame debugger (imshow error): %s", exc)
                self._failed = True
                break

        try:
            cv2.destroyWindow(self.window_name)
        except Exception:
            pass

    def _annotate_frame(
        self,
        frame: np.ndarray,
        *,
        status: Optional[str] = None,
        errors: Optional[Iterable] = None,
    ) -> np.ndarray:
        """Overlay minimal info to make debugging easier."""
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


stream_debugger = FrameDebugger(
    enabled=settings.STREAM_DEBUG_SHOW_FRAMES,
    window_name=settings.STREAM_DEBUG_WINDOW_NAME,
    max_queue=settings.STREAM_DEBUG_MAX_QUEUE,
)

__all__ = ["stream_debugger", "FrameDebugger"]
