"""
Step 7: Accessories and filter detection (VLM-based, optional)
"""

from typing import Dict, Any, List, Optional
import json
import logging
import threading
import time

import cv2
import numpy as np
from PIL import Image
import torch
from transformers import AutoModel, AutoTokenizer

from app.validators.base import BaseValidator
from app.core.errors import ValidationResult, ErrorCode
from app.core import settings
from app.utils.image_utils import crop_face_region

# Dedicated logger so we can emit load/inference issues without failing the whole pipeline
logger = logging.getLogger(__name__)


class AccessoriesValidator(BaseValidator):
    """
    Detects accessories and filters using MiniCPM-o 2.6 (vision-language model).
    
    The validator is optional and can be toggled via the API flag. It is designed
    to run on a T4 GPU (float16) when available and falls back to CPU if needed.
    """

    def __init__(
        self,
        enabled: bool = False,
        model_id: str = "openbmb/MiniCPM-o-2_6",
        max_image_side: int = 1024,
        revision: Optional[str] = None,
    ):
        super().__init__()
        self.enabled = enabled
        self.model_id = model_id
        self.max_image_side = max_image_side
        self.device = settings.TORCH_DEVICE
        self.revision = revision or settings.MINICPM_REVISION
        self._model = None
        self._tokenizer = None
        self._model_lock = threading.Lock()
        self._inference_device = "cpu"
        self._load_failed = False

        self._prompt = (
            "You are checking a passport/ID photo for forbidden accessories. "
            "Focus only on the person and respond in strict JSON. "
            "Accessories include glasses or sunglasses, tinted lenses, hats/caps/hoods, "
            "scarves or head coverings, headphones or earbuds, masks or face coverings, "
            "and jewelry such as earrings, nose rings, lip rings, heavy necklaces, or hair ornaments. "
            "Also flag obvious digital filters, beautification, stickers, AI edits, or heavy airbrushing. "
            "Return JSON only with keys: "
            "{\"accessories_detected\": <true|false>, \"filters_detected\": <true|false>, "
            "\"items\": [\"list accessories or filters\"], \"reasoning\": \"short reason\"}. "
            "If unsure, err on the side of marking accessories_detected=true."
        )

    def validate(self, image: np.ndarray, context: Dict[str, Any] = None) -> ValidationResult:
        """
        Detect accessories and filters in the provided image.

        Args:
            image: Input image as numpy array (BGR format)
            context: Optional context from previous validators (face bbox, etc.)

        Returns:
            ValidationResult
        """
        result = self._create_result()
        context = context or {}

        if not self.enabled:
            result.metadata = {
                "vlm_enabled": False,
                "message": "VLM validation is disabled",
            }
            return result

        if self._load_failed:
            result.metadata = {
                "vlm_enabled": True,
                "vlm_error": "Previous MiniCPM-o load failed",
                "model_id": self.model_id,
                "revision": self.revision,
            }
            return result

        try:
            detection = self._detect_with_vlm(image, context)

            result.metadata = detection
            if detection.get("accessories_detected"):
                result.add_error(
                    ErrorCode.ACCESSORIES_DETECTED,
                    detection.get("reasoning") or "Accessories detected by MiniCPM-o",
                )
            if detection.get("filters_detected"):
                result.add_error(
                    ErrorCode.FILTERS_DETECTED,
                    detection.get("reasoning") or "Filters or digital edits detected by MiniCPM-o",
                )
        except Exception as exc:
            logger.exception("Accessories VLM validation failed: %s", exc)
            result.metadata = {
                "vlm_enabled": True,
                "vlm_error": str(exc),
                "model_id": self.model_id,
            }

        return result

    def _detect_with_vlm(self, image: np.ndarray, context: Dict[str, Any]) -> Dict[str, Any]:
        """Run MiniCPM-o on the (optionally cropped) image and parse its response."""
        self._ensure_model_loaded()

        face_bbox = context.get("face_bbox")
        prepared_image = self._prepare_image(image, face_bbox)

        msgs = [{"role": "user", "content": [prepared_image, self._prompt]}]

        start = time.perf_counter()
        with torch.no_grad():
            response = self._model.chat(msgs=msgs, tokenizer=self._tokenizer)
        latency_ms = round((time.perf_counter() - start) * 1000, 2)

        parsed = self._parse_response(response)
        parsed.update(
            {
                "vlm_enabled": True,
                "model_id": self.model_id,
                "raw_response": response,
                "latency_ms": latency_ms,
                "used_face_crop": face_bbox is not None,
                "face_crop_bbox": face_bbox,
                "inference_device": self._inference_device,
                "revision": self.revision,
                "attn_implementation": getattr(self, "_attn_impl", None),
            }
        )

        return parsed

    def _ensure_model_loaded(self) -> None:
        """Lazy-load MiniCPM-o model/tokenizer with a shared lock."""
        if self._model is not None and self._tokenizer is not None:
            return
        if self._load_failed:
            raise RuntimeError("MiniCPM-o load previously failed")

        with self._model_lock:
            if self._model is not None and self._tokenizer is not None:
                return

            logger.info("Loading MiniCPM-o model for accessories check (%s)...", self.model_id)
            target_device = self._resolve_device()
            dtype = torch.float16 if target_device in {"cuda", "mps"} else torch.float32
            self._inference_device = target_device

            attn_impl = "sdpa"
            load_kwargs = {
                "trust_remote_code": True,
                "revision": self.revision,
                "torch_dtype": dtype,
                "attn_implementation": attn_impl,
                "low_cpu_mem_usage": True,
            }
            if target_device != "cpu":
                load_kwargs["device_map"] = {"": target_device}
            try:
                self._tokenizer = AutoTokenizer.from_pretrained(
                    self.model_id,
                    trust_remote_code=True,
                    revision=self.revision,
                )
                self._model = AutoModel.from_pretrained(
                    self.model_id,
                    **load_kwargs,
                ).eval()
            except Exception as exc:
                logger.warning(
                    "MiniCPM-o load with attn=%s failed (%s); retrying with eager",
                    attn_impl,
                    exc,
                )
                attn_impl = "eager"
                load_kwargs["attn_implementation"] = attn_impl
                try:
                    self._model = AutoModel.from_pretrained(
                        self.model_id,
                        **load_kwargs,
                    ).eval()
                except Exception:
                    self._load_failed = True
                    raise

            if target_device != "cpu":
                self._model = self._model.to(target_device)
            # Remember which attention backend we ended up using
            self._attn_impl = attn_impl

    def _prepare_image(self, image: np.ndarray, face_bbox: Optional[List[int]]) -> Image.Image:
        """
        Convert to RGB PIL image, optionally crop around the face, and downscale
        to keep inference fast on T4.
        """
        img_for_model = image
        if face_bbox is not None:
            try:
                img_for_model = crop_face_region(image, face_bbox, margin=0.35)
            except Exception as exc:
                logger.warning("Failed to crop face region for accessories check: %s", exc)

        rgb_image = cv2.cvtColor(img_for_model, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(rgb_image).convert("RGB")

        if max(pil_image.size) > self.max_image_side:
            pil_image.thumbnail((self.max_image_side, self.max_image_side))

        return pil_image

    def _parse_response(self, response: str) -> Dict[str, Any]:
        """
        Parse MiniCPM-o response. The prompt asks for JSON, but we also fall back
        to keyword heuristics if the model drifts.
        """
        parsed = {
            "accessories_detected": False,
            "filters_detected": False,
            "items": [],
            "reasoning": None,
        }

        if not response:
            parsed["reasoning"] = "Empty response from MiniCPM-o"
            return parsed

        text = response.strip()

        # Try to extract JSON block if the model wrapped it with extra text
        json_candidate = None
        if "{" in text and "}" in text:
            json_candidate = text[text.find("{") : text.rfind("}") + 1]

        if json_candidate:
            try:
                data = json.loads(json_candidate)
                parsed["accessories_detected"] = self._to_bool(
                    data.get("accessories_detected")
                    or data.get("accessories")
                    or data.get("has_accessories")
                )
                parsed["filters_detected"] = self._to_bool(
                    data.get("filters_detected")
                    or data.get("filters")
                    or data.get("beautification")
                )
                items = data.get("items") or data.get("accessories_list") or []
                if isinstance(items, list):
                    parsed["items"] = [str(item) for item in items]
                parsed["reasoning"] = data.get("reasoning") or text
                return parsed
            except Exception:
                # Fall back to heuristics below
                logger.debug("Failed to parse JSON from MiniCPM-o response: %s", text)

        lowered = text.lower()
        accessories_keywords = [
            "glasses",
            "sunglass",
            "goggles",
            "hat",
            "cap",
            "hood",
            "headphone",
            "earbud",
            "earring",
            "mask",
            "scarf",
            "veil",
            "jewelry",
            "necklace",
        ]
        filter_keywords = ["filter", "beautified", "airbrush", "edited", "retouch"]

        parsed["accessories_detected"] = any(keyword in lowered for keyword in accessories_keywords)
        parsed["filters_detected"] = any(keyword in lowered for keyword in filter_keywords)
        parsed["reasoning"] = text

        detected_items = [kw for kw in accessories_keywords if kw in lowered]
        if detected_items:
            parsed["items"] = detected_items

        return parsed

    def warmup(self) -> None:
        """Eagerly load model/tokenizer on startup."""
        if not self.enabled:
            return
        self._ensure_model_loaded()

    @staticmethod
    def _to_bool(value: Any) -> bool:
        """Robust boolean parsing for VLM JSON output."""
        if isinstance(value, str):
            return value.strip().lower() in {"true", "yes", "y", "1"}
        return bool(value)

    def _resolve_device(self) -> str:
        """
        Pick the best available device respecting the configured preference.
        Tries CUDA, then MPS for Apple Silicon, then CPU.
        """
        preferred = (self.device or "").lower()

        if preferred.startswith("cuda") and torch.cuda.is_available():
            return preferred

        if preferred == "mps":
            try:
                if torch.backends.mps.is_available() and torch.backends.mps.is_built():
                    return "mps"
            except Exception:
                # mps module presence can differ across torch builds
                pass

        if torch.cuda.is_available():
            return "cuda"

        try:
            if torch.backends.mps.is_available() and torch.backends.mps.is_built():
                return "mps"
        except Exception:
            pass

        return "cpu"
